{-# LANGUAGE DataKinds #-}
module DiffSummarySpec where

import Prologue
import Data.Record
import Test.Hspec
import Test.Hspec.QuickCheck
import Diff
import Syntax
import Term
import Patch
import Category
import DiffSummary
import Text.PrettyPrint.Leijen.Text (pretty)
import Test.Hspec.QuickCheck
import Diff.Arbitrary
import Data.List (partition)
import Term.Arbitrary
import Interpreter
import Info
import SourceSpan

arrayInfo :: Record '[Category, SourceSpan]
arrayInfo = ArrayLiteral .: SourceSpan "test.js" (SourcePos 0 0) (SourcePos 0 3) .: RNil

literalInfo :: Record '[Category, SourceSpan]
literalInfo = StringLiteral .: SourceSpan "test.js" (SourcePos 0 0) (SourcePos 0 1) .: RNil

testDiff :: Diff Text (Record '[Category, SourceSpan])
testDiff = free $ Free (pure arrayInfo :< Indexed [ free $ Pure (Insert (cofree $ literalInfo :< Leaf "a")) ])

testSummary :: DiffSummary DiffInfo
testSummary = DiffSummary { patch = Insert (LeafInfo "string" "a"), parentAnnotations = [] }

replacementSummary :: DiffSummary DiffInfo
replacementSummary = DiffSummary { patch = Replace (LeafInfo "string" "a") (LeafInfo "symbol" "b"), parentAnnotations = [ ArrayLiteral ] }

spec :: Spec
spec = parallel $ do
  describe "diffSummary" $ do
    it "outputs a diff summary" $ do
      diffSummary testDiff `shouldBe` [ DiffSummary { patch = Insert (LeafInfo "string" "a"), parentAnnotations = [ ArrayLiteral ] } ]

    prop "equal terms produce identity diffs" $
      \ a -> let term = toTerm (a :: ArbitraryTerm Text (Record '[Category, SourceSpan])) in
        diffSummary (diffTerms wrap (==) diffCost term term) `shouldBe` []

  describe "annotatedSummaries" $ do
    it "should print adds" $
      annotatedSummaries testSummary `shouldBe` ["Added the 'a' string"]
    it "prints a replacement" $ do
      annotatedSummaries replacementSummary `shouldBe` ["Replaced the 'a' string with the 'b' symbol in the array context"]
  describe "DiffInfo" $ do
    prop "patches in summaries match the patches in diffs" $
      \a -> let
        diff = (toDiff (a :: ArbitraryDiff Text (Record '[Category, Cost, SourceSpan])))
        summaries = diffSummary diff
        patches = toList diff
        in
          case (partition isBranchNode (patch <$> summaries), partition isIndexedOrFixed patches) of
            ((branchPatches, otherPatches), (branchDiffPatches, otherDiffPatches)) ->
              (() <$ branchPatches, () <$ otherPatches) `shouldBe` (() <$ branchDiffPatches, () <$ otherDiffPatches)
    prop "generates one LeafInfo for each child in an arbitrary branch patch" $
      \a -> let
        diff = (toDiff (a :: ArbitraryDiff Text (Record '[Category, SourceSpan])))
        diffInfoPatches = patch <$> diffSummary diff
        syntaxPatches = toList diff
        extractLeaves :: DiffInfo -> [DiffInfo]
        extractLeaves (BranchInfo children _ _) = join $ extractLeaves <$> children
        extractLeaves leaf = [ leaf ]

        extractDiffLeaves :: Term Text (Record '[Category, SourceSpan]) -> [ Term Text (Record '[Category, SourceSpan]) ]
        extractDiffLeaves term = case unwrap term of
          (Indexed children) -> join $ extractDiffLeaves <$> children
          (Fixed children) -> join $ extractDiffLeaves <$> children
          Commented children leaf -> children <> maybeToList leaf >>= extractDiffLeaves
          _ -> [ term ]
        in
          case (partition isBranchNode diffInfoPatches, partition isIndexedOrFixed syntaxPatches) of
            ((branchPatches, _), (diffPatches, _)) ->
              let listOfLeaves = foldMap extractLeaves (join $ toList <$> branchPatches)
                  listOfDiffLeaves = foldMap extractDiffLeaves (diffPatches >>= toList)
               in
                length listOfLeaves `shouldBe` length listOfDiffLeaves

isIndexedOrFixed :: Patch (Term a annotation) -> Bool
isIndexedOrFixed = any (isIndexedOrFixed' . unwrap)

isIndexedOrFixed' :: Syntax a f -> Bool
isIndexedOrFixed' syntax = case syntax of
  (Indexed _) -> True
  (Fixed _) -> True
  _ -> False

isBranchInfo :: DiffInfo -> Bool
isBranchInfo info = case info of
  (BranchInfo _ _ _) -> True
  (LeafInfo _ _) -> False

isBranchNode :: Patch DiffInfo -> Bool
isBranchNode = any isBranchInfo
