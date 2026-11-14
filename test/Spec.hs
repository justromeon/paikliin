module Main (main) where

import ApiSpec qualified
import DomainSpec qualified
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
  DomainSpec.spec
  ApiSpec.spec
