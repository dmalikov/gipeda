{-# LANGUAGE OverloadedStrings, DeriveDataTypeable, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleInstances #-}
module Development.Shake.Gitlib
    ( defaultRuleGitLib
    , getGitContents
    , doesGitFileExist
    , readGitFile
    ) where

import System.IO
import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Functor
import Data.Maybe


import Development.Shake
import Development.Shake.Rule
import Development.Shake.Classes

import Data.Text.Binary

import Git
import Git.Libgit2
import Data.Tagged

type RepoPath = FilePath

newtype GetGitReferenceQ = GetGitReferenceQ (RepoPath, RefName)
    deriving (Typeable,Eq,Hashable,Binary,NFData,Show)

newtype GitSHA = GitSHA T.Text
    deriving (Typeable,Eq,Hashable,Binary,NFData,Show)

newtype GetGitFileRefQ = GetGitFileRefQ (RepoPath, RefName, FilePath)
    deriving (Typeable,Eq,Hashable,Binary,NFData,Show)

instance Rule GetGitReferenceQ GitSHA where
    storedValue _ (GetGitReferenceQ (repoPath, name)) = do
        Just . GitSHA <$> getGitReference' repoPath name

instance Rule GetGitFileRefQ (Maybe T.Text) where
    storedValue _ (GetGitFileRefQ (repoPath, name, filename)) = do
        ref' <- getGitReference' repoPath name
        Just <$> getGitFileRef' repoPath ref' filename

getGitContents :: RepoPath -> Action [FilePath]
getGitContents repoPath = do
    GitSHA ref' <- apply1 $ GetGitReferenceQ (repoPath, "HEAD")
    liftIO $ withRepository lgFactory repoPath $ do
        ref <- parseOid ref'
        commit <- lookupCommit (Tagged ref)
        tree <- lookupTree (commitTree commit)
        entries <- listTreeEntries tree
        return $ map (BS.unpack . fst) entries

getGitReference' :: RepoPath -> RefName -> IO T.Text
getGitReference' repoPath refName = do
    withRepository lgFactory repoPath $ do
        Just ref <- resolveReference refName
        return $ renderOid ref

getGitFileRef' :: RepoPath -> T.Text -> FilePath -> IO (Maybe T.Text)
getGitFileRef' repoPath ref' fn = do
    withRepository lgFactory repoPath $ do
        ref <- parseOid ref'
        commit <- lookupCommit (Tagged ref)
        tree <- lookupTree (commitTree commit)
        entry <- treeEntry tree (BS.pack fn)
        case entry of
            Just (BlobEntry ref _) -> return $ Just $ renderObjOid ref
            _ -> return Nothing

doesGitFileExist :: RepoPath -> FilePath -> Action Bool
doesGitFileExist repoPath fn = do
    res <- apply1 $ GetGitFileRefQ (repoPath, "HEAD", fn)
    return $ isJust (res :: Maybe T.Text)

readGitFile :: FilePath -> FilePath -> Action BS.ByteString
readGitFile repoPath fn = do
    res <- apply1 $ GetGitFileRefQ (repoPath, "HEAD", fn)
    case res of
        Nothing -> fail "readGitFile: File does not exist"
        Just ref' -> liftIO $ withRepository lgFactory repoPath $ do
            ref <- parseOid ref'
            catBlob (Tagged ref)

defaultRuleGitLib :: Rules ()
defaultRuleGitLib = do
    rule $ \(GetGitReferenceQ (repoPath, refName)) -> Just $ liftIO $
        GitSHA <$> getGitReference' repoPath refName
    rule $ \(GetGitFileRefQ (repoPath, refName, fn)) -> Just $ do
        GitSHA ref' <- apply1 $ GetGitReferenceQ (repoPath, "HEAD")
        liftIO $ getGitFileRef' repoPath ref' fn

