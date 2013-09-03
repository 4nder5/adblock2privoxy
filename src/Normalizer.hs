module Normalizer where
import InputParser
import Control.Applicative hiding (many)
import Text.ParserCombinators.Parsec hiding (Line, (<|>))
import Control.Monad.State
import Data.List
import Data.String.Utils (replace)
import Data.Maybe
import Data.List.Utils (split)
import ParsecExt
import Utils
 
opa s = case parseUrl s of
        Left e -> putStrLn $ show e
        Right urls -> putStrLn $ intercalate "\n" $ makePattern <$> urls  
 
fixLines :: [Line] -> [Line]
fixLines = join . fmap fixLine

fixLine :: Line -> [Line]
fixLine  (Line text (ElementHide                  restr  excl pattern)) 
       = [Line text (ElementHide (fixRestrictions restr) excl pattern)]
 
fixLine  (Line text                     requestBlock@(RequestBlock _ _ _)) 
       =  Line text <$> fixRequestBlock requestBlock 
          where    
              fixRequestBlock      (RequestBlock excl                       pattern                  options)
                             = case RequestBlock excl <<$> (fixBlockPattern pattern) $>> (fixOptions options) of
                                    Right res     -> res
                                    Left  problem -> [Error $ show problem]
              fixRequestBlock _ = undefined
                             
              fixOptions (RequestOptions                  restrRt  tp                  restrDom  mc coll dnt u) 
                        = RequestOptions (fixRestrictions restrRt) tp (fixRestrictions restrDom) mc coll dnt u 
              
              fixBlockPattern :: Pattern -> Either ParseError [Pattern]
              fixBlockPattern pattern = makePattern <<$> (parseUrl pattern)
                                                   
         
fixLine a = [a]

fixRestrictions :: (Eq a) => Restrictions a -> Restrictions a
fixRestrictions = annigilate.allowAll.deduplicate
        where 
        deduplicate (Restrictions (Just p) n) = Restrictions (Just $ nub p) (nub n)
        deduplicate a = a
        allowAll (Restrictions (Just []) n@(_:_)) = Restrictions Nothing n
        allowAll a = a
        annigilate (Restrictions (Just p) n) = 
                            let notN x = x `notElem` n
                            in Restrictions (Just $ filter notN p) n
        annigilate a = a
        

data SideBind = Hard | Soft | None deriving (Show, Eq) 

data UrlPattern = UrlPattern { 
                   _bindStart :: SideBind,
                   _proto :: String,
                   _host :: String,
                   _query :: String,
                   _bindEnd :: SideBind,
                   _regex :: Bool }
              deriving (Show)

makePattern :: UrlPattern -> Pattern
makePattern (UrlPattern bindStart proto host query bindEnd isRegex) =  if query' == "/" 
                                                                            then host' 
                                                                            else host' ++ query' 
    where 
        host' = case host of
                    "" -> ""
                    _  -> changeFirst.changeLast $ host
                    where
                    changeLast []     = []
                    changeLast [lst]  
                        | lst == '|' || lst `elem` hostSeparators   =  []      
                        | lst == '*' || lst == '\0'                 =  "*."
                        | otherwise                                 =  lst : "*."
                    changeLast (c:cs) = c : changeLast cs
 
                    changeFirst []    = []
                    changeFirst (first:cs) 
                        | first == '*'                       =       '.' :  '*'  : cs
                        | bindStart /= None || proto /= ""   =             first : cs      
                        | otherwise                          = '.' : '*' : first : cs
                                    
        query' = case query of
                    ""     -> ""
                    (c:cs) -> if isRegex then '/' : query
                              else replaceFirst c ++ (join . map replaceWildcard $ cs) ++ queryEnd 
                    where                  
                    replaceFirst '*' = "/.*"
                    replaceFirst c
                        | c == '/' || c == '^' = if openStart
                                                 then "/(.*" ++ replaceWildcard c ++ ")?"
                                                 else "/"
                        | otherwise            = if openStart 
                                                 then "/.*" ++ replaceWildcard c
                                                 else '/' : replaceWildcard c
                        where 
                        openStart = bindStart == None && host == ""
                    
                    queryEnd = if bindEnd == None then "" else "$"
                                                      
                    replaceWildcard c
                        | c == '^'         = "[^\\w%.-]"
                        | c == '*'         = ".*"
                        | c `elem` special = '\\' : [c]
                        | otherwise        = [c]
                        where special = "?$.+[]{}()\\|" -- also ^ and * are special
                     

hostSeparators :: String
hostSeparators = "^/"

parseUrl :: Pattern -> Either ParseError [UrlPattern]
parseUrl =  
    let  raw = makeUrls <$> bindStart <*> cases urlParts <*> bindEnd
    in   parse (join <$> (fmap.fmap) postfilter raw) "url"
    where
        makeUrls start mid end = makeUrl <$> pure start <*> mid <*> pure end
        makeUrl start (proto, host, query) end = UrlPattern start proto host query end False
        
        bindStart = (try (Soft <$ string "||") <|> try (Hard <$ string "|") <|> return None) <?> "query start" 
        queryEnd = (char '|' <* eof) <|> ('\0' <$ eof) <|> (char '\0') <?> "query end"
        bindEnd = (\c -> if c == '|' then Hard else None) <$> queryEnd
        port = option False $ (many1 $ noneOf ":") *> char ':' *> (many1 (digit <|> char '*')) *> (optionMaybe $ oneOf "/^") *> (True <$ queryEnd)
        
        hostChar :: Parser Char
        hostChar = alphaNum <|> oneOf ".-:"
        
        protocols :: [String]
        protocols = ["https://", "http://"]
        
        protocolsSeparator :: String
        protocolsSeparator = ";"
        
        protocolChar :: Parser Char
        protocolChar = oneOf (delete '/' $ nub $ join protocols)
        
        postfilter :: UrlPattern -> [UrlPattern]
        postfilter url@(UrlPattern bs proto host query be _) = regular ++ regex ++ www
            where 
                regex = if     proto == "" 
                            && host == "" 
                            && "/" `isPrefixOf` query 
                            && length query > 2
                            && "/" `isSuffixOf` query 
                            then 
                                let query' = take (length query - 2) . drop 1 $ query
                                in [UrlPattern bs "" "" query' be True] 
                            else []
                regular = let 
                             leftBound = bs /= None || proto /= ""
                             rightBound = be /= None || query /= ""
                             orphanQuery = leftBound && host == "" && query /= "" && not ("*" `isPrefixOf` query)
                             duplicateHostStar = host == "*"
                             hostHasDot = isJust $ find (\c -> c == '.' || c == '*') host
                             firstLevelHost = not hostHasDot && leftBound && rightBound 
                             hasLegalPort = case parse port "host" host of
                                                Right val -> val
                                                _ -> False  
                             hasIllegalPort = not hasLegalPort && ":" `isInfixOf` host
                          in if not (orphanQuery || duplicateHostStar || firstLevelHost || hasIllegalPort) 
                             then
                                let
                                    query' = if "*" `isSuffixOf` host && query /= "" then '*' : query else query 
                                in [url {_query = query'}] 
                             else []
                www = case regular of
                            [regular'] -> if    bs == Soft 
                                             && proto == ""
                                             && host /= ""
                                             && not ("*" `isPrefixOf` host)
                                             && not ("." `isPrefixOf` host) 
                                          then [regular' {_host = "www." ++ host} ] 
                                          else []
                            _ -> [] 
        
        urlParts :: [StringStateParser (String,String,String)]
        urlParts = square3 proto (manyCases host) (oneCase query)
            where          
                append xs x = xs ++ [x]
                proto :: StringStateParser String
                proto = do
                        masksString <- get
                        case masksString of 
                            Nothing -> 
                                do
                                put $ Just $ intercalate protocolsSeparator protocols
                                return "" --allow to skip proto
                            Just masksString' -> 
                                do
                                let masks = split protocolsSeparator masksString'
                                if null masks 
                                    then lift pzero -- no continuations available (parser have finished on previous iteration)
                                    else 
                                        do
                                        lift $ skipMany $ char '*' --skip leading * if presented
                                        name <- lift $ many protocolChar
                                        sep <- lift $ many $ oneOf hostSeparators
                                        let chars = name ++ replace "^" "//" sep -- concatenate input and expand separator wildcard
                                        nextChar <- lift $ lookAhead anyChar
                                        let masks' = filterProtoMasks masks chars nextChar -- find possible continuations for current input
                                        if null masks' || null chars
                                            then lift pzero -- fail parser if no continuations or no chars read
                                            else
                                                do
                                                put $ Just $ if isJust (find null masks')  -- if empty continuation found (i.e. parser finished)
                                                                then "" -- make no continuations available next time
                                                                else intercalate protocolsSeparator masks'  
                                                return $ if nextChar == '*' then chars ++ "*" else chars
                host = try (append <$> many hostChar <*> char '*') <|>
                       try (append <$> many1 hostChar <*> lookAhead separator) <?> "host"
                separator = (oneOf hostSeparators <|> queryEnd) <?> "separator"
                query = notFollowedBy (try $ string "//") *> manyTill anyChar (lookAhead (try queryEnd)) <?> "query"
                
                filterProtoMasks :: [String] -> String -> Char -> [String]
                filterProtoMasks masks chars nextChar = mapMaybe filterProtoMask masks
                    where filterProtoMask mask = if nextChar /= '*' 
                                    then if chars `isSuffixOf` mask
                                         then Just ""
                                         else Nothing 
                                    else let tailFound = find (chars `isPrefixOf`) (tails mask)
                                         in drop (length chars) <$> tailFound 
                
        




            


