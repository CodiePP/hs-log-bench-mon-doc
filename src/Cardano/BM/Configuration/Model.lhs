
\subsection{Cardano.BM.Configuration.Model}
\label{module:Cardano.BM.Configuration.Model}

%if style == newcode
\begin{code}
{-# LANGUAGE OverloadedStrings   #-}

module Cardano.BM.Configuration.Model
    ( Configuration (..)
    , ConfigurationInternal (..)
    , setup
    , empty
    , minSeverity
    , setMinSeverity
    , inspectSeverity
    , setSeverity
    , getBackends
    , setBackend
    , getDefaultBackends
    , setDefaultBackends
    , setSetupBackends
    , getSetupBackends
    , getScribes
    , setScribe
    , setDefaultScribes
    , setSetupScribes
    , getSetupScribes
    , getAggregatedKind
    , setDefaultAggregatedKind
    , setAggregatedKind
    , getOption
    , findSubTrace
    , setSubTrace
    , getEKGport
    , setEKGport
    , getGUIport
    , setGUIport
    --, takedown
    ) where

import           Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar,
                     takeMVar, withMVar)
import qualified Data.HashMap.Strict as HM
import           Data.Maybe (catMaybes)
import           Data.Text (Text, pack, unpack)
import qualified Data.Vector as Vector
import           Data.Yaml as Y

import           Cardano.BM.Data.AggregatedKind (AggregatedKind(..))
import           Cardano.BM.Data.BackendKind
import qualified Cardano.BM.Data.Configuration as R
import           Cardano.BM.Data.LogItem (LoggerName)
import           Cardano.BM.Data.Observable
import           Cardano.BM.Data.Output (ScribeDefinition, ScribeId)
import           Cardano.BM.Data.Severity
import           Cardano.BM.Data.SubTrace

\end{code}
%endif

\subsubsection{Configuration.Model}\label{code:Configuration}
\begin{figure}[htp]
\centering{
  \includegraphics[scale=0.54]{ConfigurationModel.pdf}
}
\caption{Configuration model}\label{fig:configuration}
\end{figure}

\begin{code}
type ConfigurationMVar = MVar ConfigurationInternal
newtype Configuration = Configuration
    { getCG :: ConfigurationMVar }

-- Our internal state; see {-"\nameref{fig:configuration}"-}
data ConfigurationInternal = ConfigurationInternal
    { cgMinSeverity       :: Severity
    -- minimum severity level of every object that will be output
    , cgMapSeverity       :: HM.HashMap LoggerName Severity
    -- severity filter per loggername
    , cgMapSubtrace       :: HM.HashMap LoggerName SubTrace
    -- type of trace per loggername
    , cgOptions           :: HM.HashMap Text Object
    -- options needed for tracing, logging and monitoring
    , cgMapBackend        :: HM.HashMap LoggerName [BackendKind]
    -- backends that will be used for the specific loggername
    , cgDefBackendKs      :: [BackendKind]
    -- backends that will be used if a set of backends for the
    -- specific loggername is not set
    , cgSetupBackends     :: [BackendKind]
    -- backends to setup; every backend to be used must have
    -- been declared here
    , cgMapScribe         :: HM.HashMap LoggerName [ScribeId]
    -- katip scribes that will be used for the specific loggername
    , cgDefScribes        :: [ScribeId]
    -- katip scribes that will be used if a set of scribes for the
    -- specific loggername is not set
    , cgSetupScribes      :: [ScribeDefinition]
    -- katip scribes to setup; every scribe to be used must have
    -- been declared here
    , cgMapAggregatedKind :: HM.HashMap LoggerName AggregatedKind
    -- kind of Aggregated that will be used for the specific loggername
    , cgDefAggregatedKind :: AggregatedKind
    -- kind of Aggregated that will be used if a set of scribes for the
    -- specific loggername is not set
    , cgPortEKG           :: Int
    -- port for EKG server
    , cgPortGUI           :: Int
    -- port for changes at runtime (NOT IMPLEMENTED YET)
    } deriving (Show, Eq)

\end{code}

\subsubsection{Backends configured in the |Switchboard|}
For a given context name return the list of backends configured,
or, in case no such configuration exists, return the default backends.
\begin{code}
getBackends :: Configuration -> LoggerName -> IO [BackendKind]
getBackends configuration name =
    withMVar (getCG configuration) $ \cg -> do
        let outs = HM.lookup name (cgMapBackend cg)
        case outs of
            Nothing -> do
                return (cgDefBackendKs cg)
            Just os -> return os

getDefaultBackends :: Configuration -> IO [BackendKind]
getDefaultBackends configuration =
    withMVar (getCG configuration) $ \cg -> do
        return (cgDefBackendKs cg)

setDefaultBackends :: Configuration -> [BackendKind] -> IO ()
setDefaultBackends configuration bes = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgDefBackendKs = bes }

setBackend :: Configuration -> LoggerName -> Maybe [BackendKind] -> IO ()
setBackend configuration name be = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgMapBackend = HM.alter (\_ -> be) name (cgMapBackend cg) }

\end{code}

\subsubsection{Backends to be setup by the |Switchboard|}
Defines the list of |Backend|s that need to be setup by the |Switchboard|.
\begin{code}
setSetupBackends :: Configuration -> [BackendKind] -> IO ()
setSetupBackends configuration bes = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgSetupBackends = bes }

getSetupBackends :: Configuration -> IO [BackendKind]
getSetupBackends configuration =
    withMVar (getCG configuration) $ \cg ->
        return $ cgSetupBackends cg

\end{code}


\subsubsection{Scribes configured in the |Log| backend}
For a given context name return the list of scribes to output to,
or, in case no such configuration exists, return the default scribes to use.
\begin{code}
getScribes :: Configuration -> LoggerName -> IO [ScribeId]
getScribes configuration name =
    withMVar (getCG configuration) $ \cg -> do
        let outs = HM.lookup name (cgMapScribe cg)
        case outs of
            Nothing -> do
                return (cgDefScribes cg)
            Just os -> return $ os

setDefaultScribes :: Configuration -> [ScribeId] -> IO ()
setDefaultScribes configuration scs = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgDefScribes = scs }

setScribe :: Configuration -> LoggerName -> Maybe [ScribeId] -> IO ()
setScribe configuration name be = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgMapScribe = HM.alter (\_ -> be) name (cgMapScribe cg) }

\end{code}

\subsubsection{Scribes to be setup in the |Log| backend}
Defines the list of |Scribe|s that need to be setup in the |Log| backend.
\begin{code}
setSetupScribes :: Configuration -> [ScribeDefinition] -> IO ()
setSetupScribes configuration sds = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgSetupScribes = sds }

getSetupScribes :: Configuration -> IO [ScribeDefinition]
getSetupScribes configuration =
    withMVar (getCG configuration) $ \cg -> do
        return $ cgSetupScribes cg

\end{code}

\subsubsection{|AggregatedKind| to define the type of measurement}
For a given context name return its |AggregatedKind| or in case no
such configuration exists, return the default |AggregatedKind| to use.
\begin{code}
getAggregatedKind :: Configuration -> LoggerName -> IO AggregatedKind
getAggregatedKind configuration name =
    withMVar (getCG configuration) $ \cg -> do
        let outs = HM.lookup name (cgMapAggregatedKind cg)
        case outs of
            Nothing -> do
                return (cgDefAggregatedKind cg)
            Just os -> return $ os

setDefaultAggregatedKind :: Configuration -> AggregatedKind -> IO ()
setDefaultAggregatedKind configuration defAK = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgDefAggregatedKind = defAK }

setAggregatedKind :: Configuration -> LoggerName -> Maybe AggregatedKind -> IO ()
setAggregatedKind configuration name ak = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgMapAggregatedKind = HM.alter (\_ -> ak) name (cgMapAggregatedKind cg) }

\end{code}

\subsubsection{Access port numbers of EKG, GUI}
\begin{code}
getEKGport :: Configuration -> IO Int
getEKGport configuration =
    withMVar (getCG configuration) $ \cg -> do
        return $ cgPortEKG cg
setEKGport :: Configuration -> Int -> IO ()
setEKGport configuration port = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgPortEKG = port }

getGUIport :: Configuration -> IO Int
getGUIport configuration =
    withMVar (getCG configuration) $ \cg -> do
        return $ cgPortGUI cg
setGUIport :: Configuration -> Int -> IO ()
setGUIport configuration port = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgPortGUI = port }

\end{code}

\subsubsection{Options}
\begin{code}
getOption :: Configuration -> Text -> IO (Maybe Text)
getOption configuration name = do
    withMVar (getCG configuration) $ \cg ->
        case HM.lookup name (cgOptions cg) of
            Nothing -> return Nothing
            Just o -> return $ Just $ pack $ show o

\end{code}

\subsubsection{Global setting of minimum severity}
\begin{code}
minSeverity :: Configuration -> IO Severity
minSeverity configuration = withMVar (getCG configuration) $ \cg ->
    return $ cgMinSeverity cg

setMinSeverity :: Configuration -> Severity -> IO ()
setMinSeverity configuration sev = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgMinSeverity = sev }

\end{code}

\subsubsection{Relation of context name to minimum severity}
\begin{code}
inspectSeverity :: Configuration -> Text -> IO (Maybe Severity)
inspectSeverity configuration name = do
    withMVar (getCG configuration) $ \cg ->
        return $ HM.lookup name (cgMapSeverity cg)

setSeverity :: Configuration -> Text -> Maybe Severity -> IO ()
setSeverity configuration name sev = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgMapSeverity = HM.alter (\_ -> sev) name (cgMapSeverity cg) }

\end{code}

\subsubsection{Relation of context name to SubTrace}
A new context may contain a different type of |Trace|.
The function |appendName| (\nameref{code:appendName}) will look up the |SubTrace| for the context's name.
\begin{code}
findSubTrace :: Configuration -> Text -> IO (Maybe SubTrace)
findSubTrace configuration name = do
    withMVar (getCG configuration) $ \cg ->
        return $ HM.lookup name (cgMapSubtrace cg)

setSubTrace :: Configuration -> Text -> Maybe SubTrace -> IO ()
setSubTrace configuration name trafo = do
    cg <- takeMVar (getCG configuration)
    putMVar (getCG configuration) $ cg { cgMapSubtrace = HM.alter (\_ -> trafo) name (cgMapSubtrace cg) }

\end{code}

\subsubsection{Parse configuration from file}
Parse the configuration into an internal representation first. Then, fill in |Configuration|
after refinement.
\begin{code}
setup :: FilePath -> IO Configuration
setup fp = do
    r <- R.parseRepresentation fp
    cgref <- newEmptyMVar
    let mapseverity        = HM.lookup "mapSeverity"        (R.options r)
        mapbackends        = HM.lookup "mapBackends"        (R.options r)
        mapsubtrace        = HM.lookup "mapSubtrace"        (R.options r)
        mapscribes         = HM.lookup "mapScribes"         (R.options r)
        mapAggregatedKinds = HM.lookup "mapAggregatedkinds" (R.options r)
    putMVar cgref $ ConfigurationInternal
        { cgMinSeverity = R.minSeverity r
        , cgMapSeverity = parseSeverityMap mapseverity
        , cgMapSubtrace = parseSubtraceMap mapsubtrace
        , cgOptions = R.options r
        , cgMapBackend = parseBackendMap mapbackends
        , cgDefBackendKs = R.defaultBackends r
        , cgSetupBackends = R.setupBackends r
        , cgMapScribe = parseScribeMap mapscribes
        , cgDefScribes = r_defaultScribes r
        , cgSetupScribes = R.setupScribes r
        , cgMapAggregatedKind = parseAggregatedKindMap mapAggregatedKinds
        , cgDefAggregatedKind = StatsAK
        , cgPortEKG = r_hasEKG r
        , cgPortGUI = r_hasGUI r
        }
    return $ Configuration cgref
  where
    parseSeverityMap :: Maybe (HM.HashMap Text Value) -> HM.HashMap Text Severity
    parseSeverityMap Nothing = HM.empty
    parseSeverityMap (Just hmv) = HM.mapMaybe mkSeverity hmv
    mkSeverity (String s) = Just (read (unpack s) :: Severity)
    mkSeverity _ = Nothing

    parseBackendMap Nothing = HM.empty
    parseBackendMap (Just hmv) = HM.map mkBackends hmv
    mkBackends (Array bes) = catMaybes $ map mkBackend $ Vector.toList bes
    mkBackends _ = []
    mkBackend (String s) = Just (read (unpack s) :: BackendKind)
    mkBackend _ = Nothing

    parseScribeMap Nothing = HM.empty
    parseScribeMap (Just hmv) = HM.map mkScribes hmv
    mkScribes (Array scs) = catMaybes $ map mkScribe $ Vector.toList scs
    mkScribes (String s) = [(s :: ScribeId)]
    mkScribes _ = []
    mkScribe (String s) = Just (s :: ScribeId)
    mkScribe _ = Nothing

    parseSubtraceMap :: Maybe (HM.HashMap Text Value) -> HM.HashMap Text SubTrace
    parseSubtraceMap Nothing = HM.empty
    parseSubtraceMap (Just hmv) = HM.mapMaybe mkSubtrace hmv
    mkSubtrace (String s) = Just (read (unpack s) :: SubTrace)
    mkSubtrace (Object hm) = mkSubtrace' (HM.lookup "tag" hm) (HM.lookup "contents" hm)
    mkSubtrace _ = Nothing
    mkSubtrace' Nothing _ = Nothing
    mkSubtrace' _ Nothing = Nothing
    mkSubtrace' (Just (String tag)) (Just (Array cs)) =
        if tag == "ObservableTrace"
        then Just $ ObservableTrace $ map (\(String s) -> (read (unpack s) :: ObservableInstance)) $ Vector.toList cs
        else Nothing
    mkSubtrace' _ _ = Nothing

    r_hasEKG r = case (R.hasEKG r) of
                       Nothing -> 0
                       Just p  -> p
    r_hasGUI r = case (R.hasGUI r) of
                       Nothing -> 0
                       Just p  -> p
    r_defaultScribes r = map (\(k,n) -> pack(show k) <> "::" <> n) (R.defaultScribes r)

    parseAggregatedKindMap Nothing = HM.empty
    parseAggregatedKindMap (Just hmv) =
        let
            listv = HM.toList hmv
            mapAggregatedKind = HM.fromList $ catMaybes $ map mkAggregatedKind listv
        in
        mapAggregatedKind
    mkAggregatedKind (name, String s) = Just (name, read (unpack s) :: AggregatedKind)
    mkAggregatedKind _ = Nothing

\end{code}

\subsubsection{Setup empty configuration}
\begin{code}
empty :: IO Configuration
empty = do
    cgref <- newEmptyMVar
    putMVar cgref $ ConfigurationInternal Debug HM.empty HM.empty HM.empty HM.empty [] [] HM.empty [] [] HM.empty StatsAK 0 0
    return $ Configuration cgref

\end{code}
