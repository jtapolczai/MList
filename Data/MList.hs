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
  foldML,
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
  zipWit4ML,
  zipWit5ML,
  zipWit6ML,
  zipWith7ML,

  unzipML,
  unzip3ML,
  unzip4ML,
  unzip5ML,
  unzip6ML,
  unzip7ML,
  ) where

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

-- |Tests whether an MList is empty.
nullML :: Monad m => MList m a -> Bool
nullML MNil = True
nullML _ = False

-- |Returns the head of an MList.
headML :: Monad m => MList m a -> a
headML MNil = error "headIO: head of empty IOList"
headML (x :# _) = x

-- |Returns the tail of an MList.
tailML :: Monad m => MList m a -> m (MList m a)
tailML MNil = error "tailIO: tail of empty IOList"
tailML (_ :# xs) = xs

-- |Folds an MList from the left.
foldML :: Monad m => (a -> b -> m a) -> a -> MList m b -> m a
foldML _ acc MNil = return acc
foldML f acc (x :# xs) = do acc' <- f acc x
                            xs' <- xs
                            foldML f acc' xs'

-- |Unfolds an MList.
unfoldML :: Monad m => (b -> m (Maybe (a,b))) -> b -> m (MList m a)
unfoldML f acc = do v <- f acc
                    return (case v of Nothing       -> MNil
                                      Just (x,acc') -> x :# unfoldML f acc')

-- |Takes n elements from the beginning of an MList.
takeML :: Monad m => Int -> MList m a -> m (MList m a)
takeML n _ | n <= 0 = return MNil
takeML _ MNil = return MNil
takeML i (x :# xs) = return $ x :# (xs >>= takeML (i-1))

-- |Drops n elements from the beginning of an MList
dropML :: Monad m => Int -> MList m a -> m (MList m a)
dropML n xs | n <= 0 = return xs
dropML _ MNil = return MNil
dropML i (_ :# xs) = xs >>= dropML (i-1)

takeWhileML :: Monad m => (a -> Bool) -> MList m a -> m (MList m a)
takeWhileML _ MNil = return MNil
takeWhileML f (x :# xs) | f x       = return $ x :# (xs >>= takeWhileML f)
                        | otherwise = return MNil

dropWhileML :: Monad m => (a -> Bool) -> MList m a -> m (MList m a)
dropWhileML _ MNil = return MNil
dropWhileML f (x :# xs) | f x       = xs >>= dropWhileML f
                        | otherwise = xs

mapML :: Monad m => (a -> m b) -> MList m a -> m (MList m b)
mapML _ MNil = return MNil
mapML f (x :# xs) = do y <- f x
                       return $ y :# (xs >>= mapML f)

ioEnum :: IO (MList IO Int)
ioEnum = ioEnum' 0
  where ioEnum' i = return $ i :# ioEnum' (i+1)
