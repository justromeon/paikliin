module Main (main) where

import DomainSpec qualified
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
  DomainSpec.spec
