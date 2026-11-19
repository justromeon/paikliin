module Main (main) where

import ApiSpec qualified
import CacheSpec qualified
import DomainSpec qualified
import RateLimitSpec qualified
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
  DomainSpec.spec
  ApiSpec.spec
  CacheSpec.spec
  RateLimitSpec.spec
