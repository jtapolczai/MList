{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleInstances #-}

{- |Operations on monadic lists (MLists). The functions in this module
    largely mirror those found in 'Data.List'.
    
    Monadic lists make it possible to lazily generate streams of
    monadic values, which regular lists can't do. An example:

    @
getMeasurement :: IO Int
getMeasurement = ...

measurementStream :: IO [Int]
measurementStream = do x <- getMeasurement
                xs <- measurementStream
                return (x:xs)
    @

    Because @getMeasurement@ is monadic, it's not possible to extract
    anything from @measurementStream@ - @head measurementStream@ will not
    terminate because, thanks to the IO monad, the @xs@ it its body
    will be computed before the @return@.

    The data type @MList m a@ solves this problem with a modified @:@ -
    instead of @a : [a]@, an MList has @a :# m [a]@. The @m@ in the tail
    is a monad and allows the confinement of the eager, monadic computation.

    We can thus rewrite @measurementStream@ to be useful again:

@
measurementStream :: IO (MList IO Int)
measurementStream = do x <- getMeasurement
                       return (x :# measurementStream)
@
-}
module Data.MList (
  -- * Conversion to and from lists
  fromMList,
  toMList,

  -- * Show class for MLists
  MShow(..),

  -- * Basic operations
  (+++),
  headML,
  lastML,
  tailML,
  initML,
  nullML,
  lengthML,

  -- * Transformations
  mapML,
  reverseML,

  -- * Folds
  foldlML,
  foldrML,
  unfoldML,

  -- * Accumulating maps
  mapAccumML,

  -- * Infinite MLists
  iterateML,
  repeatML,
  replicateML,
  cycleML,

  -- * Sublists
  takeML,
  dropML,
  takeWhileML,
  dropWhileML,

  -- * Searching MLists
  elemML,
  notElemML,

  -- * Zipping MLists
  zipML,
  zip3ML,
  zip4ML,
  zip5ML,
  zip6ML,
  zip7ML,

  zipWithML,
  zipWith3ML,
  zipWith4ML,
  zipWith5ML,
  zipWith6ML,
  zipWith7ML,

  unzipML,
  unzip3ML,
  unzip4ML,
  unzip5ML,
  unzip6ML,
  unzip7ML,
  ) where

import Control.Monad

-- |A list of type @a@ whose tail has type @m [a]@ instead of @[a]@.
--  This allows for the lazy generation of elements, even if the list
--  is a stream of monadic values.
data MList m a = MNil | a :# (m (MList m a))
infix 5 :#

-- |Monadic version of 'Show'.
class Monad m => MShow m a | a -> m where
  showM :: a -> m String

instance (Monad m, Show a) => MShow m (MList m a) where
  showM xs = case xs of MNil     -> return "[]"
                        (_ :# _) -> do content <- showM' xs
                                       return $ "[" ++ content ++ "]"
    where 
          showM' MNil = return ""
          showM' (x :# xs') = do xs'' <- xs'
                                 rest <- showM' xs''
                                 let sep = case xs'' of MNil -> ""
                                                        _    -> ","
                                 return $ show x ++ sep ++ rest

-- |Turns a monad list into a regular list.
fromMList :: Monad m => MList m a -> m [a]
fromMList MNil = return []
fromMList (x :# xs) = do xs' <- xs >>= fromMList
                         return $ x : xs'

-- |Turns a regular list into an MList
toMList :: Monad m => [a] -> MList m a
toMList [] = MNil
toMList (x:xs) = x :# return (toMList xs)

-- |Concatenates two MLists.
(+++) :: Monad m => MList m a -> MList m a -> MList m a
MNil +++ ys = ys
(x :# xs) +++ ys = x :# liftM (+++ ys) xs

-- |Tests whether an MList is empty.
nullML :: Monad m => MList m a -> Bool
nullML MNil = True
nullML _ = False

-- |Returns the length of an MList.
lengthML :: Monad m => MList m a -> m Int
lengthML = foldlML (\x _ -> return (x+1)) 0

-- |Returns the head of an MList.
headML :: Monad m => MList m a -> a
headML MNil = error "headML: head of empty MList!"
headML (x :# _) = x

-- |Returns the tail of an MList.
tailML :: Monad m => MList m a -> m (MList m a)
tailML MNil = error "tailML: tail of empty MList!"
tailML (_ :# xs) = xs

-- |Returns an MList without its last element.
initML :: Monad m => MList m a -> MList m a
initML MNil = error "initML: init of an empty MList!"
initML (x :# xs) = x :# liftM initML xs

-- |Returns the last element of an MList.
lastML :: Monad m => MList m a -> m a
lastML MNil = error "lastML: last of an empty MList!"
lastML (x :# xs) = do xs' <- xs
                      case xs' of MNil      -> return x
                                  (_ :# _) -> lastML xs'

-- |Folds an MList from the left.
foldlML :: Monad m => (a -> b -> m a) -> a -> MList m b -> m a
foldlML _ acc MNil = return acc
foldlML f acc (x :# xs) = do acc' <- f acc x
                             xs' <- xs
                             foldlML f acc' xs'

foldrML :: Monad m => (a -> b -> m b) -> b -> MList m a -> m b
foldrML _ acc MNil = return acc
foldrML f acc (x :# xs) = do y <- (f x acc)
                             xs' <- xs
                             foldrML f y xs'

-- |Unfolds an MList.
unfoldML :: Monad m => (b -> m (Maybe (a,b))) -> b -> m (MList m a)
unfoldML f acc = do v <- f acc
                    return (case v of Nothing       -> MNil
                                      Just (x,acc') -> x :# unfoldML f acc')

-- |Takes n elements from the beginning of an MList.
takeML :: Monad m => Int -> MList m a -> MList m a
takeML n _ | n <= 0 = MNil
takeML _ MNil = MNil
takeML i (x :# xs) = x :# liftM (takeML (i-1)) xs

-- |Drops n elements from the beginning of an MList
dropML :: Monad m => Int -> MList m a -> m (MList m a)
dropML n xs | n <= 0 = return xs
dropML _ MNil = return MNil
dropML i (_ :# xs) = xs >>= dropML (i-1)

-- |Takes elements of an MList as long as a predicate is fulfilled.
takeWhileML :: Monad m => (a -> Bool) -> MList m a -> MList m a
takeWhileML _ MNil = MNil
takeWhileML f (x :# xs) | f x       = x :# liftM (takeWhileML f) xs
                        | otherwise = MNil

-- |Drops elements from an MList as long as a predicate is fulfilled.
dropWhileML :: Monad m => (a -> Bool) -> MList m a -> m (MList m a)
dropWhileML _ MNil = return MNil
dropWhileML f (x :# xs) | f x       = xs >>= dropWhileML f
                        | otherwise = xs

-- |Applies a function to every element of an MList.
mapML :: Monad m => (a -> m b) -> MList m a -> m (MList m b)
mapML _ MNil = return MNil
mapML f (x :# xs) = do y <- f x
                       return $ y :# (xs >>= mapML f)

-- |Reverses an MList.
reverseML :: Monad m => MList m a -> m (MList m a)
reverseML = reverse' MNil
  where reverse' acc MNil = return acc
        reverse' acc (x :# xs) = xs >>= reverse' (x :# return acc)

-- |Combines 'foldML' and 'mapML', both applying a function to
--  every element and accumulating a value.
mapAccumML :: Monad m
           => (acc -> a -> m (acc, b))
           -> acc
           -> MList m a
           -> m (acc, MList m b)
mapAccumML _ acc MNil = return (acc, MNil)
mapAccumML f acc (x :# xs) = do (acc', y) <- f acc x
                                (acc'', ys) <- xs >>= mapAccumML f acc'
                                return (acc'', y :# return ys)

-- |Constructs the infinite MList @[x, f x, f (f x), ...]@.
iterateML :: Monad m => (a -> m a) -> a -> MList m a
iterateML f x = x :# liftM (iterateML f) (f x)

-- |Repeats the same element infinitely.
repeatML :: Monad m => m a -> m (MList m a)
repeatML x = do x' <- x
                return $ x' :# repeatML x

-- |Creates an MList consisting of n copies of an element.
replicateML :: Monad m => Int -> m a -> m (MList m a)
replicateML n x | n <= 0 = return MNil
                | n > 0  = do x' <- x
                              return (x' :# replicateML (n-1) x) 

-- |Repeats an MList infinitely.
cycleML :: Monad m => MList m a -> MList m a
cycleML MNil = error "cycleML: tail of empty MList!"
cycleML xs = xs +++ cycleML xs

-- |Returns True if an MList contains a given element.
--  If the list is infinite, this is only a semi-decision procedure.
elemML :: (Monad m, Eq a) => a -> MList m a -> m Bool
elemML _ MNil = return False
elemML x (y :# ys) | x == y    = return True
                   | otherwise = ys >>= elemML y

-- |The negation of 'elemML'.
notElemML :: (Monad m, Eq a) => a -> MList m a -> m Bool
notElemML x ys = liftM not (elemML x ys)

-- |Zips two MLists.
zipML :: Monad m
      => MList m a
      -> MList m b
      -> MList m (a,b)
zipML = zipWithML (,)

-- |Zips three MLists.
zip3ML :: Monad m
       => MList m a
       -> MList m b
       -> MList m c
       -> MList m (a,b,c)
zip3ML = zipWith3ML (,,)

-- |Zips four MLists.
zip4ML :: Monad m
       => MList m a
       -> MList m b
       -> MList m c
       -> MList m d
       -> MList m (a,b,c,d)
zip4ML = zipWith4ML (,,,)

-- |Zips five MLists.
zip5ML :: Monad m
       => MList m a
       -> MList m b
       -> MList m c
       -> MList m d
       -> MList m e
       -> MList m (a,b,c,d,e)
zip5ML = zipWith5ML (,,,,)

-- |Zips six MLists.
zip6ML :: Monad m
       => MList m a
       -> MList m b
       -> MList m c
       -> MList m d
       -> MList m e
       -> MList m f
       -> MList m (a,b,c,d,e,f)
zip6ML = zipWith6ML (,,,,,)

-- |Zips seven MLists.
zip7ML :: Monad m
       => MList m a
       -> MList m b
       -> MList m c
       -> MList m d
       -> MList m e
       -> MList m f
       -> MList m g
       -> MList m (a,b,c,d,e,f,g)
zip7ML = zipWith7ML (,,,,,,)

-- |Zips two lists with a function.
zipWithML :: Monad m
        => (a -> b -> c)
        -> MList m a
        -> MList m b
        -> MList m c
zipWithML f (x :# xs) (y :# ys) =
  (f x y) :# do xs' <- xs
                ys' <- ys
                return (zipWithML f xs' ys')
zipWithML _ _ _ = MNil

-- |Zips three lists with a function.
zipWith3ML :: Monad m
        => (a -> b -> c -> d)
        -> MList m a
        -> MList m b
        -> MList m c
        -> MList m d
zipWith3ML f (x :# xs) (y :# ys) (z :# zs) =
  (f x y z) :# do xs' <- xs
                  ys' <- ys
                  zs' <- zs
                  return (zipWith3ML f xs' ys' zs')
zipWith3ML _ _ _ _ = MNil

-- |Zips four lists with a function.
zipWith4ML :: Monad m
        => (a -> b -> c -> d -> e)
        -> MList m a
        -> MList m b
        -> MList m c
        -> MList m d
        -> MList m e
zipWith4ML f (x :# xs) (y :# ys) (z :# zs) (u :# us) =
  (f x y z u) :# do xs' <- xs
                    ys' <- ys
                    zs' <- zs
                    us' <- us
                    return (zipWith4ML f xs' ys' zs' us')
zipWith4ML _ _ _ _ _ = MNil

-- |Zips five lists with a function.
zipWith5ML :: Monad m
        => (a -> b -> c -> d -> e -> f)
        -> MList m a
        -> MList m b
        -> MList m c
        -> MList m d
        -> MList m e
        -> MList m f
zipWith5ML f (x :# xs) (y :# ys) (z :# zs) (u :# us) (v :# vs) =
  (f x y z u v) :# do xs' <- xs
                      ys' <- ys
                      zs' <- zs
                      us' <- us
                      vs' <- vs
                      return (zipWith5ML f xs' ys' zs' us' vs')
zipWith5ML _ _ _ _ _ _ = MNil

-- |Zips six lists with a function.
zipWith6ML :: Monad m
        => (a -> b -> c -> d -> e -> f -> g)
        -> MList m a
        -> MList m b
        -> MList m c
        -> MList m d
        -> MList m e
        -> MList m f
        -> MList m g
zipWith6ML f (x :# xs) (y :# ys) (z :# zs) (u :# us) (v :# vs) (w :# ws) =
  (f x y z u v w) :# do xs' <- xs
                        ys' <- ys
                        zs' <- zs
                        us' <- us
                        vs' <- vs
                        ws' <- ws
                        return (zipWith6ML f xs' ys' zs' us' vs' ws')
zipWith6ML _ _ _ _ _ _ _ = MNil

-- |Zips seven lists with a function.
zipWith7ML :: Monad m
        => (a -> b -> c -> d -> e -> f -> g -> h)
        -> MList m a
        -> MList m b
        -> MList m c
        -> MList m d
        -> MList m e
        -> MList m f
        -> MList m g
        -> MList m h
zipWith7ML f (x :# xs) (y :# ys) (z :# zs) (u :# us) (v :# vs) (w :# ws) (a :# as) =
  (f x y z u v w a) :# do xs' <- xs
                          ys' <- ys
                          zs' <- zs
                          us' <- us
                          vs' <- vs
                          ws' <- ws
                          as' <- as
                          return (zipWith7ML f xs' ys' zs' us' vs' ws' as')
zipWith7ML _ _ _ _ _ _ _ _ = MNil

-- |Transforms a list of pairs into a list of components.
unzipML :: Monad m
        => MList m (a,b)
        -> m (MList m a, MList m b)
unzipML = foldrML (\(a,b) (as,bs) -> return (a :# return as, b :# return bs))
                  (MNil, MNil)

-- |Transforms a list of pairs into a list of components.
unzip3ML :: Monad m
        => MList m (a,b,c)
        -> m (MList m a, MList m b, MList m c)
unzip3ML = foldrML (\(a,b,c) (as,bs,cs) -> return (a :# return as, b :# return bs, c :# return cs))
                   (MNil, MNil, MNil)

-- |Transforms a list of pairs into a list of components.
unzip4ML :: Monad m
        => MList m (a,b,c,d)
        -> m (MList m a, MList m b, MList m c, MList m d)
unzip4ML = foldrML (\(a,b,c,d) (as,bs,cs,ds) -> return (a :# return as, b :# return bs, c :# return cs,
                                                        d :# return ds))
                   (MNil, MNil, MNil, MNil)

-- |Transforms a list of pairs into a list of components.
unzip5ML :: Monad m
        => MList m (a,b,c,d,e)
        -> m (MList m a, MList m b, MList m c, MList m d, MList m e)
unzip5ML = foldrML (\(a,b,c,d,e) (as,bs,cs,ds,es) -> return (a :# return as, b :# return bs, c :# return cs,
                                                             d :# return ds, e :# return es))
                   (MNil, MNil, MNil, MNil, MNil)

-- |Transforms a list of pairs into a list of components.
unzip6ML :: Monad m
        => MList m (a,b,c,d,e,f)
        -> m (MList m a, MList m b, MList m c, MList m d, MList m e, MList m f)
unzip6ML = foldrML (\(a,b,c,d,e,f) (as,bs,cs,ds,es,fs) -> return (a :# return as, b :# return bs, c :# return cs,
                                                                  d :# return ds, e :# return es, f :# return fs))
                   (MNil, MNil, MNil, MNil, MNil, MNil)

-- |Transforms a list of pairs into a list of components.
unzip7ML :: Monad m
        => MList m (a,b,c,d,e,f,g)
        -> m (MList m a, MList m b, MList m c, MList m d, MList m e, MList m f, MList m g)
unzip7ML = foldrML (\(a,b,c,d,e,f,g) (as,bs,cs,ds,es,fs,gs) -> return (a :# return as, b :# return bs, c :# return cs,
                                                                       d :# return ds, e :# return es, f :# return fs,
                                                                       g :# return gs))
                   (MNil, MNil, MNil, MNil, MNil, MNil, MNil)
