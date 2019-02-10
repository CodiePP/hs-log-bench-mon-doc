
\subsection{Cardano.BM.Data.MonitoringEval}

%if style == newcode
\begin{code}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}

module Cardano.BM.Data.MonitoringEval
  ( MEvExpr (..)
  , MEvAction
  , VarName
  , Environment
  , evaluate
  , parseEither
  , parseMaybe
  , test1, test2, test3, test4
  )
  where

import           Control.Applicative ((<|>))
import           Control.Monad (void)
import           Data.Aeson (FromJSON (..), Value (..))
import qualified Data.Attoparsec.Text as P
import           Data.Char (isSpace)
import qualified Data.HashMap.Strict as HM
import           Data.Text (Text, unpack)
import           Data.Word (Word64)

import           Cardano.BM.Data.Aggregated
import           Cardano.BM.Data.Severity

\end{code}
%endif

\subsubsection{Expressions}\label{code:MEvExpr}
Evaluation in monitoring will evaluate expressions
\begin{code}
type VarName = Text
data MEvExpr = Compare VarName (Measurable -> Measurable -> Bool, Measurable)
             | AND MEvExpr MEvExpr
             | OR MEvExpr MEvExpr
             | NOT MEvExpr

            -- parsing: "(some >= (2000 µs))"  =>  Compare "some" ((>=), (Microseconds 2000))
            -- parser "((lastreported >= (5 s)) Or ((other >= (0 s)) And (some > (1500 µs))))"

instance Eq MEvExpr where
    (==) (Compare vn1 _) (Compare vn2 _) = vn1 == vn2
    (==) (AND e11 e12) (AND e21 e22)     = (e11 == e21 && e12 == e22)    -- || (e11 == e22 && e12 == e21)
    (==) (OR e11 e12) (OR e21 e22)       = (e11 == e21 && e12 == e22)    -- || (e11 == e22 && e12 == e21)
    (==) (NOT e1) (NOT e2)               = (e1 == e2)
    (==) _ _ = False

instance FromJSON MEvExpr where
    parseJSON (String s) =
        case parseEither s of
            Left e     -> error e
            Right expr -> pure expr
    parseJSON _ = error "cannot parse such an expression!"

instance Show MEvExpr where
    show (Compare vn _) = "compare " ++ (unpack vn)
    show (AND e1 e2)    = "(" ++ (show e1) ++ ") And (" ++ (show e2) ++ ")"
    show (OR e1 e2)    = "(" ++ (show e1) ++ ") Or (" ++ (show e2) ++ ")"
    show (NOT e)    = "Not (" ++ (show e) ++ ")"
\end{code}

\subsubsection{Monitoring actions}\label{code:MEvAction}
If evaluation of a monitoring expression is |True|, then a set of actions are
executed for alerting.
\begin{code}
type MEvAction = Text

\end{code}

\subsubsection{Parsing an expression from textual representation}\label{code:parseEither}\label{code:parseMaybe}
\begin{code}
parseEither :: Text -> Either String MEvExpr
parseEither t =
    let r = P.parse parseExpr t
    in
    P.eitherResult r

parseMaybe :: Text -> Maybe MEvExpr
parseMaybe t =
    let r = P.parse parseExpr t
    in
    P.maybeResult r

openPar, closePar :: P.Parser ()
openPar = void $ P.char '('
closePar = void $ P.char ')'
token :: Text -> P.Parser ()
token s = void $ P.string s

\end{code}

\label{code:parseExpr}
An expression is enclosed in parentheses. Either it is a negation, starting with 'Not',
or a binary operand like 'And', 'Or', or a comparison of a named variable.
\begin{code}
parseExpr :: P.Parser MEvExpr
parseExpr = do
    openPar
    P.skipSpace
    e <- do
            (nextIsChar 'N' >> parseNot)
        <|> (nextIsChar '(' >> parseBi)
        <|> parseComp
    P.skipSpace
    closePar
    return e

\end{code}

\label{code:nextIsChar}
\begin{code}
nextIsChar :: Char -> P.Parser ()
nextIsChar c = do
    c' <- P.peekChar'
    if c == c'
    then return ()
    else fail $ "cannot parse char: " ++ [c]

parseBi :: P.Parser MEvExpr
parseBi = do
    e1 <- parseExpr
    P.skipSpace
    op <-     (token "And" >> return AND)
          <|> (token "Or" >> return OR)
    P.skipSpace
    e2 <- parseExpr
    return (op e1 e2)

parseNot :: P.Parser MEvExpr
parseNot = do
    token "Not"
    P.skipSpace
    e <- parseExpr
    P.skipSpace
    return (NOT e)

parseComp :: P.Parser MEvExpr
parseComp = do
    vn <- parseVname
    P.skipSpace
    op <- parseOp
    P.skipSpace
    m <- parseMeasurable
    return $ Compare vn (op, m)

parseVname :: P.Parser VarName
parseVname = do
    P.takeTill (isSpace)

parseOp :: (Ord a, Eq a) => P.Parser (a -> a -> Bool)
parseOp = do
        (P.string ">=" >> return (>=))
    <|> (P.string "==" >> return (==))
    <|> (P.string "/=" >> return (/=))
    <|> (P.string "!=" >> return (/=))
    <|> (P.string "<>" >> return (/=))
    <|> (P.string "<=" >> return (<=))
    <|> (P.string "<"  >> return (<))
    <|> (P.string ">"  >> return (>))

parseMeasurable :: P.Parser Measurable
parseMeasurable = do
    openPar
    P.skipSpace
    m <- parseMeasurable'
    P.skipSpace
    closePar
    return m
parseMeasurable' :: P.Parser Measurable
parseMeasurable' =
        parseTime
    <|> parseBytes
    <|> parseSeverity
    <|> (P.double >>= return . PureD)
    <|> (P.decimal >>= return . PureI)

parseTime :: P.Parser Measurable
parseTime = do
    n <- P.decimal
    P.skipSpace
    tryUnit n
  where
    tryUnit :: Word64 -> P.Parser Measurable
    tryUnit n =
            (P.string "ns" >> return (Nanoseconds n))
        <|> (P.string "µs" >> return (Microseconds n))
        <|> (P.string "s"  >> return (Seconds n))

parseBytes :: P.Parser Measurable
parseBytes = do
    n <- P.decimal
    P.skipSpace
    tryUnit n
  where
    tryUnit :: Word64 -> P.Parser Measurable
    tryUnit n =
            (P.string "kB"    >> return (Bytes (n * 1000)))
        <|> (P.string "bytes" >> return (Bytes n))
        <|> (P.string "byte"  >> return (Bytes n))
        <|> (P.string "MB"    >> return (Bytes (n * 1000 * 1000)))
        <|> (P.string "GB"    >> return (Bytes (n * 1000 * 1000 * 1000)))

parseSeverity :: P.Parser Measurable
parseSeverity =
        (P.string "Debug"     >> return (Severity Debug))
    <|> (P.string "Info"      >> return (Severity Info))
    <|> (P.string "Notice"    >> return (Severity Notice))
    <|> (P.string "Warning"   >> return (Severity Warning))
    <|> (P.string "Error"     >> return (Severity Error))
    <|> (P.string "Critical"  >> return (Severity Critical))
    <|> (P.string "Alert"     >> return (Severity Alert))
    <|> (P.string "Emergency" >> return (Severity Emergency))
\end{code}

\subsubsection{Evaluate expression}\label{code:Environment}\label{code:evaluate}
This is an interpreter of |MEvExpr| in an |Environment|.
\begin{code}
type Environment = HM.HashMap VarName Measurable

\end{code}

The actual interpreter of an expression returns |True|
if the expression is valid in the |Environment|,
otherwise returns |False|.
\begin{code}
evaluate :: Environment -> MEvExpr -> Bool
evaluate ev expr =
    case expr of
        Compare vn (op, m2) ->
                     case getMeasurable ev vn of
                        Nothing -> False
                        Just m1 -> op m1 m2
        AND e1 e2 -> (evaluate ev e1) && (evaluate ev e2)
        OR e1 e2  -> (evaluate ev e1) || (evaluate ev e2)
        NOT e     -> not (evaluate ev e)

\end{code}

Helper functions to extract named values from the |Environment|.
\begin{code}
getMeasurable :: Environment -> VarName -> Maybe Measurable
getMeasurable ev vn = HM.lookup vn ev

\end{code}



\begin{code}
test1 :: MEvExpr
test1 = Compare "some" ((>), (Microseconds 2000))

test2 :: MEvExpr
test2 = Compare "other" ((==), (Severity Error))

test3 :: MEvExpr
test3 = OR test1 (NOT test2)

test4 :: Bool
test4 =
    let env = HM.fromList [("some", Microseconds 1999), ("other", Severity Error)]
    in
    evaluate env test3
\end{code}