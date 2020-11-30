{-# LANGUAGE NoOverloadedStrings #-} -- prevent trouble if turned on in ghci
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Checkdates (
  checkdatesmode
 ,checkdates
) where

import Hledger
import Hledger.Cli.CliOptions
import System.Console.CmdArgs.Explicit
import System.Exit
import Text.Printf

checkdatesmode :: Mode RawOpts
checkdatesmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Checkdates.txt")
  [flagNone ["unique"] (setboolopt "unique") "require that dates are unique"]
  [generalflagsgroup1]
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

checkdates :: CliOpts -> Journal -> IO ()
checkdates CliOpts{rawopts_=rawopts,reportspec_=rspec} j = do
  let ropts = (rsOpts rspec){accountlistmode_=ALFlat}
  let ts = filter (rsQuery rspec `matchesTransaction`) $
           jtxns $ journalSelectingAmountFromOpts ropts j
  -- pprint rawopts
  let unique = boolopt "--unique" rawopts  -- TEMP: it's this for hledger check dates
            || boolopt "unique" rawopts    -- and this for hledger check-dates (for some reason)
  let date = transactionDateFn ropts
  let compare a b =
        if unique
        then date a <  date b
        else date a <= date b
  case checkTransactions compare ts of
    FoldAcc{fa_previous=Nothing} -> return ()
    FoldAcc{fa_error=Nothing}    -> return ()
    FoldAcc{fa_error=Just error, fa_previous=Just previous} -> do
      putStrLn $ printf 
          ("Error: transaction's date is not in date order%s,\n"
        ++ "at %s:\n\n%sPrevious transaction's date was: %s")
        (if unique then " and/or not unique" else "")
        (showGenericSourcePos $ tsourcepos error)
        (showTransaction error)
        (show $ date previous)
      exitFailure

data FoldAcc a b = FoldAcc
 { fa_error    :: Maybe a
 , fa_previous :: Maybe b
 }

foldWhile :: (a -> FoldAcc a b -> FoldAcc a b) -> FoldAcc a b -> [a] -> FoldAcc a b
foldWhile _ acc [] = acc
foldWhile fold acc (a:as) =
  case fold a acc of
   acc@FoldAcc{fa_error=Just _} -> acc
   acc -> foldWhile fold acc as

checkTransactions :: (Transaction -> Transaction -> Bool)
 -> [Transaction] -> FoldAcc Transaction Transaction
checkTransactions compare = foldWhile f FoldAcc{fa_error=Nothing, fa_previous=Nothing}
  where
    f current acc@FoldAcc{fa_previous=Nothing} = acc{fa_previous=Just current}
    f current acc@FoldAcc{fa_previous=Just previous} =
      if compare previous current
      then acc{fa_previous=Just current}
      else acc{fa_error=Just current}
