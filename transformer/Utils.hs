module Utils where

import Control.Monad (liftM)
import Data.Set (Set)
import qualified Data.Set as Set

import Language.Python.Common.AST (ModuleSpan)
import Language.Python.Common.ParseError (ParseError)
import Language.Python.Common.Pretty (pretty, render, Pretty)
--import Language.Python.Common.PrettyAST ()
import Language.Python.Version3.Parser (parseExpr, parseStmt, parseModule)

import Names (namesExpr, namesStmts, namesModule)
import Simplifier (simplExpr, simplStmts, simplModule, evalNameGen)
import Instrumentation (instModule)

getNames :: (String -> String -> Either ParseError (a,b)) -> (a -> Set String) -> String -> Set String
getNames parse names = either (const Set.empty) (names . fst) . flip parse "" . (++"\n")

parseNamesInExpr :: String -> Set String
parseNamesInExpr = getNames parseExpr namesExpr

parseNamesInStmt :: String -> Set String
parseNamesInStmt = getNames parseStmt namesStmts

parseNamesInModule :: String -> Set String
parseNamesInModule = getNames parseModule namesModule

parseNamesInModuleIO :: String -> IO (Set String)
parseNamesInModuleIO fname = parseNamesInModule `liftM` readFile fname

mapLeft :: (e -> a) -> Either e b -> Either a b
mapLeft f (Left e)  = Left $ f e
mapLeft _ (Right b) = Right b

simplifyExpr :: String -> IO ()
simplifyExpr str = putStrLn $ either (("Error: "++) . show) prettify simplified
  where simplified = mapLeft show parsed >>= simplify
        parsed = parseExpr str ""
        names = parseNamesInExpr str
        simplify (ast, _) = evalNameGen names $ simplExpr ast
        prettify (stmts, expr) = prettyStmts ++ prettyExpr
          where prettyStmts = "Stmts: " ++ concatMap (("\n  "++) . render . pretty) stmts ++ "\n"
                prettyExpr = "Expr: " ++ render (pretty expr)
-- > simplifyExpr "tmp_2 + tmp_6 * (tmp_1 - tmp_9) * tmp_8"
-- Stmts: 
--   tmp_3 = tmp_1 - tmp_9
--   tmp_4 = tmp_6 * tmp_3
--   tmp_5 = tmp_4 * tmp_8
-- Expr: tmp_2 + tmp_5

simplifyStmt :: String -> IO ()
simplifyStmt str = putStrLn $ either (("Error: "++) . show) prettify simplified
  where simplified = mapLeft show parsed >>= simplify
        parsed = parseStmt (str ++ "\n") ""
        names = parseNamesInStmt str
        simplify (ast, _) = evalNameGen names $ simplStmts ast
        prettify = concatMap ((++"\n") . render . pretty)
-- > simplifyStmt "if a+4 > b:\n a = b * a + 42\nelif b < 2*a:\n b = 2*a + 2*b + c**4\nelse:\n b = a * (b - 7)"

simplifyModule :: String -> Either String ModuleSpan
simplifyModule file = case parseModule (file++"\n") "" of
  Left e         -> Left $ show e
  Right (ast, _) -> evalNameGen (parseNamesInModule file) $ simplModule ast
-- > let Right mod = simplifyModule "a=c(d,e,42)"
-- > putPretty $ instModule mod

simplifyModuleIO :: String -> IO ()
simplifyModuleIO = moduleIO simplifyModule
-- > simplifyModuleIO "../interpreter/tests/simple1.py"

instrumentModule :: String -> Either String ModuleSpan
instrumentModule file = simplifyModule file >>= instModule

instrumentModuleIO :: String -> IO ()
instrumentModuleIO = moduleIO instrumentModule

moduleIO :: (String -> Either String ModuleSpan) -> String -> IO ()
moduleIO fun fname = readFile fname >>= putStrLn . either ("Error: "++) (render . pretty) . fun

putPretty :: Pretty a => a -> IO ()
putPretty = putStrLn . render . pretty
