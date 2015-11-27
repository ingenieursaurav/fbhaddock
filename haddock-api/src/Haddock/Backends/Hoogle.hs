-----------------------------------------------------------------------------
-- |
-- Module      :  Haddock.Backends.Hoogle
-- Copyright   :  (c) Neil Mitchell 2006-2008
-- License     :  BSD-like
--
-- Maintainer  :  haddock@projects.haskell.org
-- Stability   :  experimental
-- Portability :  portable
--
-- Write out Hoogle compatible documentation
-- http://www.haskell.org/hoogle/
-----------------------------------------------------------------------------
module Haddock.Backends.Hoogle (
    ppHoogle
  ) where


import Haddock.GhcUtils
import Haddock.Types hiding (Version)
import Haddock.Utils hiding (out)
import GHC
import Outputable

import Data.Char
import Data.List
import Data.Maybe
import Data.Version
import System.FilePath
import System.IO

prefix :: [String]
prefix = ["-- Hoogle documentation, generated by Haddock"
         ,"-- See Hoogle, http://www.haskell.org/hoogle/"
         ,""]


ppHoogle :: DynFlags -> String -> Version -> String -> Maybe (Doc RdrName) -> [Interface] -> FilePath -> IO ()
ppHoogle dflags package version synopsis prologue ifaces odir = do
    let filename = package ++ ".txt"
        contents = prefix ++
                   docWith dflags (drop 2 $ dropWhile (/= ':') synopsis) prologue ++
                   ["@package " ++ package] ++
                   ["@version " ++ showVersion version
                   | not (null (versionBranch version)) ] ++
                   concat [ppModule dflags i | i <- ifaces, OptHide `notElem` ifaceOptions i]
    h <- openFile (odir </> filename) WriteMode
    hSetEncoding h utf8
    hPutStr h (unlines contents)
    hClose h

ppModule :: DynFlags -> Interface -> [String]
ppModule dflags iface =
  "" : ppDocumentation dflags (ifaceDoc iface) ++
  ["module " ++ moduleString (ifaceMod iface)] ++
  concatMap (ppExport dflags) (ifaceExportItems iface) ++
  concatMap (ppInstance dflags) (ifaceInstances iface)


---------------------------------------------------------------------
-- Utility functions

dropHsDocTy :: HsType a -> HsType a
dropHsDocTy = f
    where
        g (L src x) = L src (f x)
        f (HsForAllTy a e) = HsForAllTy a (g e)
        f (HsQualTy a e) = HsQualTy a (g e)
        f (HsBangTy a b) = HsBangTy a (g b)
        f (HsAppTy a b) = HsAppTy (g a) (g b)
        f (HsFunTy a b) = HsFunTy (g a) (g b)
        f (HsListTy a) = HsListTy (g a)
        f (HsPArrTy a) = HsPArrTy (g a)
        f (HsTupleTy a b) = HsTupleTy a (map g b)
        f (HsOpTy a b c) = HsOpTy (g a) b (g c)
        f (HsParTy a) = HsParTy (g a)
        f (HsKindSig a b) = HsKindSig (g a) b
        f (HsDocTy a _) = f $ unL a
        f x = x

outHsType :: OutputableBndr a => DynFlags -> HsType a -> String
outHsType dflags = out dflags . dropHsDocTy


dropComment :: String -> String
dropComment (' ':'-':'-':' ':_) = []
dropComment (x:xs) = x : dropComment xs
dropComment [] = []


out :: Outputable a => DynFlags -> a -> String
out dflags = f . unwords . map (dropWhile isSpace) . lines . showSDocUnqual dflags . ppr
    where
        f xs | " <document comment>" `isPrefixOf` xs = f $ drop 19 xs
        f (x:xs) = x : f xs
        f [] = []


operator :: String -> String
operator (x:xs) | not (isAlphaNum x) && x `notElem` "_' ([{" = '(' : x:xs ++ ")"
operator x = x


---------------------------------------------------------------------
-- How to print each export

ppExport :: DynFlags -> ExportItem Name -> [String]
ppExport dflags ExportDecl { expItemDecl    = L _ decl
                           , expItemMbDoc   = (dc, _)
                           , expItemSubDocs = subdocs
                           } = ppDocumentation dflags dc ++ f decl
    where
        f (TyClD d@DataDecl{})  = ppData dflags d subdocs
        f (TyClD d@SynDecl{})   = ppSynonym dflags d
        f (TyClD d@ClassDecl{}) = ppClass dflags d
        f (ForD (ForeignImport name typ _ _)) = pp_sig dflags [name] (hsSigType typ)
        f (ForD (ForeignExport name typ _ _)) = pp_sig dflags [name] (hsSigType typ)
        f (SigD sig) = ppSig dflags sig
        f _ = []
ppExport _ _ = []


ppSig :: DynFlags -> Sig Name -> [String]
ppSig dflags (TypeSig names sig) = pp_sig dflags names (hsSigWcType sig)
ppSig _ _ = []

pp_sig :: DynFlags -> [Located Name] -> LHsType Name -> [String]
pp_sig dflags names (L _ typ)
  = [operator prettyNames ++ " :: " ++ outHsType dflags typ]
  where
    prettyNames = intercalate ", " $ map (out dflags) names

-- note: does not yet output documentation for class methods
ppClass :: DynFlags -> TyClDecl Name -> [String]
ppClass dflags x = out dflags x{tcdSigs=[]} :
                   concatMap (ppSig dflags . unL . add_ctxt) (tcdSigs x)
  where
    add_ctxt = addClassContext (tcdName x) (tyClDeclTyVars x)

ppInstance :: DynFlags -> ClsInst -> [String]
ppInstance dflags x = [dropComment $ out dflags x]


ppSynonym :: DynFlags -> TyClDecl Name -> [String]
ppSynonym dflags x = [out dflags x]

ppData :: DynFlags -> TyClDecl Name -> [(Name, DocForDecl Name)] -> [String]
ppData dflags decl@(DataDecl { tcdDataDefn = defn }) subdocs
    = showData decl{ tcdDataDefn = defn { dd_cons=[],dd_derivs=Nothing }} :
      concatMap (ppCtor dflags decl subdocs . unL) (dd_cons defn)
    where

        -- GHC gives out "data Bar =", we want to delete the equals
        -- also writes data : a b, when we want data (:) a b
        showData d = unwords $ map f $ if last xs == "=" then init xs else xs
            where
                xs = words $ out dflags d
                nam = out dflags $ tyClDeclLName d
                f w = if w == nam then operator nam else w
ppData _ _ _ = panic "ppData"

-- | for constructors, and named-fields...
lookupCon :: DynFlags -> [(Name, DocForDecl Name)] -> Located Name -> [String]
lookupCon dflags subdocs (L _ name) = case lookup name subdocs of
  Just (d, _) -> ppDocumentation dflags d
  _ -> []

ppCtor :: DynFlags -> TyClDecl Name -> [(Name, DocForDecl Name)] -> ConDecl Name -> [String]
ppCtor dflags dat subdocs con@ConDeclH98 {}
  -- AZ:TODO get rid of the concatMap
   = concatMap (lookupCon dflags subdocs) [con_name con] ++ f (con_details con)
    where
        f (PrefixCon args) = [typeSig name $ args ++ [resType]]
        f (InfixCon a1 a2) = f $ PrefixCon [a1,a2]
        f (RecCon (L _ recs)) = f (PrefixCon $ map cd_fld_type (map unLoc recs)) ++ concat
                          [(concatMap (lookupCon dflags subdocs . noLoc . selectorFieldOcc . unLoc) (cd_fld_names r)) ++
                           [out dflags (map (selectorFieldOcc . unLoc) $ cd_fld_names r) `typeSig` [resType, cd_fld_type r]]
                          | r <- map unLoc recs]

        funs = foldr1 (\x y -> reL $ HsFunTy x y)
        apps = foldl1 (\x y -> reL $ HsAppTy x y)

        typeSig nm flds = operator nm ++ " :: " ++ outHsType dflags (unL $ funs flds)
        name = out dflags $ map unL $ con_names con

        resType = apps $ map (reL . HsTyVar . reL) $
                        (tcdName dat) : [hsTyVarName v | L _ v@(UserTyVar _) <- hsQTvBndrs $ tyClDeclTyVars dat]

ppCtor dflags _dat subdocs con@ConDeclGADT {}
   = concatMap (lookupCon dflags subdocs) (con_names con) ++ f
    where
        f = [typeSig name (hsib_body $ con_type con)]

        typeSig nm ty = operator nm ++ " :: " ++ outHsType dflags (unL ty)
        name = out dflags $ map unL $ con_names con


---------------------------------------------------------------------
-- DOCUMENTATION

ppDocumentation :: Outputable o => DynFlags -> Documentation o -> [String]
ppDocumentation dflags (Documentation d w) = mdoc dflags d ++ doc dflags w


doc :: Outputable o => DynFlags -> Maybe (Doc o) -> [String]
doc dflags = docWith dflags ""

mdoc :: Outputable o => DynFlags -> Maybe (MDoc o) -> [String]
mdoc dflags = docWith dflags "" . fmap _doc

docWith :: Outputable o => DynFlags -> String -> Maybe (Doc o) -> [String]
docWith _ [] Nothing = []
docWith dflags header d
  = ("":) $ zipWith (++) ("-- | " : repeat "--   ") $
    lines header ++ ["" | header /= "" && isJust d] ++
    maybe [] (showTags . markup (markupTag dflags)) d


data Tag = TagL Char [Tags] | TagP Tags | TagPre Tags | TagInline String Tags | Str String
           deriving Show

type Tags = [Tag]

box :: (a -> b) -> a -> [b]
box f x = [f x]

str :: String -> [Tag]
str a = [Str a]

-- want things like paragraph, pre etc to be handled by blank lines in the source document
-- and things like \n and \t converted away
-- much like blogger in HTML mode
-- everything else wants to be included as tags, neatly nested for some (ul,li,ol)
-- or inlne for others (a,i,tt)
-- entities (&,>,<) should always be appropriately escaped

markupTag :: Outputable o => DynFlags -> DocMarkup o [Tag]
markupTag dflags = Markup {
  markupParagraph            = box TagP,
  markupEmpty                = str "",
  markupString               = str,
  markupAppend               = (++),
  markupIdentifier           = box (TagInline "a") . str . out dflags,
  markupIdentifierUnchecked  = box (TagInline "a") . str . out dflags . snd,
  markupModule               = box (TagInline "a") . str,
  markupWarning              = box (TagInline "i"),
  markupEmphasis             = box (TagInline "i"),
  markupBold                 = box (TagInline "b"),
  markupMonospaced           = box (TagInline "tt"),
  markupPic                  = const $ str " ",
  markupUnorderedList        = box (TagL 'u'),
  markupOrderedList          = box (TagL 'o'),
  markupDefList              = box (TagL 'u') . map (\(a,b) -> TagInline "i" a : Str " " : b),
  markupCodeBlock            = box TagPre,
  markupHyperlink            = \(Hyperlink url mLabel) -> (box (TagInline "a") . str) (fromMaybe url mLabel),
  markupAName                = const $ str "",
  markupProperty             = box TagPre . str,
  markupExample              = box TagPre . str . unlines . map exampleToString,
  markupHeader               = \(Header l h) -> box (TagInline $ "h" ++ show l) h
  }


showTags :: [Tag] -> [String]
showTags = intercalate [""] . map showBlock


showBlock :: Tag -> [String]
showBlock (TagP xs) = showInline xs
showBlock (TagL t xs) = ['<':t:"l>"] ++ mid ++ ['<':'/':t:"l>"]
    where mid = concatMap (showInline . box (TagInline "li")) xs
showBlock (TagPre xs) = ["<pre>"] ++ showPre xs ++ ["</pre>"]
showBlock x = showInline [x]


asInline :: Tag -> Tags
asInline (TagP xs) = xs
asInline (TagPre xs) = [TagInline "pre" xs]
asInline (TagL t xs) = [TagInline (t:"l") $ map (TagInline "li") xs]
asInline x = [x]


showInline :: [Tag] -> [String]
showInline = unwordsWrap 70 . words . concatMap f
    where
        fs = concatMap f
        f (Str x) = escape x
        f (TagInline s xs) = "<"++s++">" ++ (if s == "li" then trim else id) (fs xs) ++ "</"++s++">"
        f x = fs $ asInline x

        trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse


showPre :: [Tag] -> [String]
showPre = trimFront . trimLines . lines . concatMap f
    where
        trimLines = dropWhile null . reverse . dropWhile null . reverse
        trimFront xs = map (drop i) xs
            where
                ns = [length a | x <- xs, let (a,b) = span isSpace x, b /= ""]
                i = if null ns then 0 else minimum ns

        fs = concatMap f
        f (Str x) = escape x
        f (TagInline s xs) = "<"++s++">" ++ fs xs ++ "</"++s++">"
        f x = fs $ asInline x


unwordsWrap :: Int -> [String] -> [String]
unwordsWrap n = f n []
    where
        f _ s [] = [g s | s /= []]
        f i s (x:xs) | nx > i = g s : f (n - nx - 1) [x] xs
                     | otherwise = f (i - nx - 1) (x:s) xs
            where nx = length x

        g = unwords . reverse


escape :: String -> String
escape = concatMap f
    where
        f '<' = "&lt;"
        f '>' = "&gt;"
        f '&' = "&amp;"
        f x = [x]
