{-
Copyright (C) 2013 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- |
   Module      : Text.Pandoc.Writers.Shared
   Copyright   : Copyright (C) 2013 John MacFarlane
   License     : GNU GPL, version 2 or above

   Maintainer  : John MacFarlane <jgm@berkeley.edu>
   Stability   : alpha
   Portability : portable

Shared utility functions for pandoc writers.
-}
module Text.Pandoc.Writers.Shared (
                       metaToJSON
                     , getField
                     , setField
                     , defField
                     )
where
import Text.Pandoc.Definition
import Control.Monad (liftM)
import Text.Pandoc.Options (WriterOptions(..))
import qualified Data.HashMap.Strict as H
import qualified Data.Map as M
import qualified Data.Text as T
import Data.Aeson (FromJSON(..), fromJSON, ToJSON (..), Value(Object), Result(..))
import qualified Data.Traversable as Traversable

-- | Create JSON value for template from a 'Meta' and an association list
-- of variables, specified at the command line or in the writer.
-- Variables overwrite metadata fields with the same names.
-- If multiple variables are set with the same name, a list is
-- assigned.
metaToJSON :: Monad m
           => WriterOptions
           -> ([Block] -> m String)
           -> ([Inline] -> m String)
           -> Meta
           -> m Value
metaToJSON opts blockWriter inlineWriter (Meta metamap)
  | writerStandalone opts = do
    let baseContext = foldl (\acc (x,y) -> setField x y acc) (Object H.empty)
                      $ writerVariables opts
    renderedMap <- Traversable.mapM
                   (metaValueToJSON blockWriter inlineWriter)
                   metamap
    return $ M.foldWithKey (\key val obj -> defField key val obj)
                   baseContext renderedMap
  | otherwise = return (Object H.empty)

metaValueToJSON :: Monad m
                => ([Block] -> m String)
                -> ([Inline] -> m String)
                -> MetaValue
                -> m Value
metaValueToJSON blockWriter inlineWriter (MetaMap metamap) = liftM toJSON $
  Traversable.mapM (metaValueToJSON blockWriter inlineWriter) metamap
metaValueToJSON blockWriter inlineWriter (MetaList xs) = liftM toJSON $
  Traversable.mapM (metaValueToJSON blockWriter inlineWriter) xs
metaValueToJSON _ _ (MetaString s) = return $ toJSON s
metaValueToJSON blockWriter _ (MetaBlocks bs) = liftM toJSON $ blockWriter bs
metaValueToJSON _ inlineWriter (MetaInlines bs) = liftM toJSON $ inlineWriter bs

-- | Retrieve a field value from a JSON object.
getField :: FromJSON a
         => String
         -> Value
         -> Maybe a
getField field (Object hashmap) = do
  result <- H.lookup (T.pack field) hashmap
  case fromJSON result of
       Success x -> return x
       _         -> fail "Could not convert from JSON"
getField _ _ = fail "Not a JSON object"

setField :: ToJSON a
         => String
         -> a
         -> Value
         -> Value
-- | Set a field of a JSON object.  If the field already has a value,
-- convert it into a list with the new value appended to the old value(s).
-- This is a utility function to be used in preparing template contexts.
setField field val (Object hashmap) =
  Object $ H.insertWith combine (T.pack field) (toJSON val) hashmap
  where combine newval oldval =
          case fromJSON oldval of
                Success xs  -> toJSON $ xs ++ [newval]
                _           -> toJSON [oldval, newval]
setField _ _  x = x

defField :: ToJSON a
         => String
         -> a
         -> Value
         -> Value
-- | Set a field of a JSON object if it currently has no value.
-- If it has a value, do nothing.
-- This is a utility function to be used in preparing template contexts.
defField field val (Object hashmap) =
  Object $ H.insertWith f (T.pack field) (toJSON val) hashmap
    where f _newval oldval = oldval
defField _ _  x = x

