
\subsection{Cardano.BM.Trace}
\label{code:Cardano.BM.Trace}

%if style == newcode
\begin{code}
{-# LANGUAGE RankNTypes        #-}

module Cardano.BM.Trace
    (
      Trace
    , stdoutTrace
    , BaseTrace.noTrace
    , traceInTVar
    , traceInTVarIO
    , traceNamedInTVarIO
    , traceInTVarIOConditionally
    , traceNamedInTVarIOConditionally
    -- * context naming
    , appendName
    , modifyName
    -- * utils
    , natTrace
    , subTrace
    , typeofTrace
    , evalFilters
    -- * log functions
    , traceNamedObject
    , traceNamedItem
    , logAlert,     logAlertS
    , logCritical,  logCriticalS
    , logDebug,     logDebugS
    , logEmergency, logEmergencyS
    , logError,     logErrorS
    , logInfo,      logInfoS
    , logNotice,    logNoticeS
    , logWarning,   logWarningS
    ) where

import           Control.Concurrent.MVar (MVar, newMVar, withMVar)
import qualified Control.Concurrent.STM.TVar as STM
import           Control.Monad.IO.Class (MonadIO, liftIO)
import qualified Control.Monad.STM as STM
import           Data.Aeson.Text (encodeToLazyText)
import           Data.Functor.Contravariant (Contravariant (..), Op (..))
import           Data.Maybe (fromMaybe)
import           Data.Monoid ((<>))
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import           Data.Text.Lazy (toStrict)
import           System.IO.Unsafe (unsafePerformIO)

import qualified Cardano.BM.BaseTrace as BaseTrace
import qualified Cardano.BM.Configuration as Config
import           Cardano.BM.Data.LogItem
import           Cardano.BM.Data.Severity
import           Cardano.BM.Data.Trace
import           Cardano.BM.Data.SubTrace

\end{code}
%endif

\subsubsection{Utilities}
Natural transformation from monad |m| to monad |n|.
\begin{code}
natTrace :: (forall x . m x -> n x) -> Trace m -> Trace n
natTrace nat (ctx, trace) = (ctx, BaseTrace.natTrace nat trace)

\end{code}

Access type of |Trace|.\label{code:typeofTrace}\index{typeofTrace}
\begin{code}
typeofTrace :: Trace m -> SubTrace
typeofTrace (ctx, _) = tracetype ctx

\end{code}

Update type of |Trace|.\label{code:updateTracetype}\index{updateTracetype}
\begin{code}
updateTracetype :: SubTrace -> Trace m -> Trace m
updateTracetype subtr (ctx, tr) = (ctx {tracetype=subtr}, tr)

\end{code}


\subsubsection{Enter new named context}\label{code:appendName}\index{appendName}
The context name is created and checked that its size is below a limit
(currently 80 chars).
The minimum severity that a log message must be labelled with is looked up in
the configuration and recalculated.
\begin{code}
appendName :: MonadIO m => LoggerName -> Trace m -> m (Trace m)
appendName name =
    modifyName (\prevLoggerName -> appendWithDot name prevLoggerName)


appendWithDot :: LoggerName -> LoggerName -> LoggerName
appendWithDot "" newName = newName
appendWithDot xs ""      = xs
appendWithDot xs newName = xs <> "." <> newName

\end{code}

\subsubsection{Change named context}\label{code:modifyName}\index{modifyName}
The context name is created and checked that its size is below a limit
(currently 80 chars).
The minimum severity that a log message must be labelled with is looked up in
the configuration and recalculated.
\begin{code}
modifyName :: MonadIO m => (LoggerName -> LoggerName) -> Trace m -> m (Trace m)
modifyName f (ctx, basetrace0) =
    let basetrace = modifyNameBase f basetrace0
    in
    return (ctx, basetrace)

modifyNameBase
    :: (LoggerName -> LoggerName)
    -> TraceNamed m
    -> TraceNamed m
modifyNameBase k = contramap f
  where
    f (LogNamed name item) = LogNamed (k name) item

\end{code}

\subsubsection{Contramap a trace and produce the naming context}
\begin{code}
named :: BaseTrace.BaseTrace m (LogNamed i) -> BaseTrace.BaseTrace m i
named = contramap (LogNamed mempty)

\end{code}

\subsubsection{Trace a |LogObject| through}
\label{code:traceNamedObject}\index{traceNamedObject}
\begin{code}
traceNamedObject
    :: MonadIO m
    => Trace m
    -> LogObject
    -> m ()
traceNamedObject trace@(_, logTrace) lo@(LogObject _ lc) = do
    doOutput <- case (typeofTrace trace) of
        FilterTrace filters ->
             case lc of
                LogValue _loname _ ->
                    return $ evalFilters filters "TODO"
                    -- (lname <> "." <> loname)
                _ ->
                    return $ evalFilters filters "TODO"
                    -- lname
        TeeTrace secName -> do
             -- create a newly named copy of the |LogObject|
             (_, logTrace') <- appendName secName trace
             BaseTrace.traceWith (named logTrace') lo
             return True
        _ -> return True
    if doOutput
    then BaseTrace.traceWith (named logTrace) lo
    else return ()

\end{code}

\subsubsection{Evaluation of |FilterTrace|}\label{code:evalFilters}\index{evalFilters}

A filter consists of a |DropName| and a list of |UnhideNames|. If the context name matches
the |DropName| filter, then at least one of the |UnhideNames| must match the name to have
the evaluation of the filters return |True|.

\begin{code}
evalFilters :: [(DropName, UnhideNames)] -> LoggerName -> Bool
evalFilters fs nm =
    all (\(no, yes) -> if (dropFilter nm no) then (unhideFilter nm yes) else True) fs
  where
    dropFilter :: LoggerName -> DropName -> Bool
    dropFilter name (Drop sel) = {-not-} (matchName name sel)
    unhideFilter :: LoggerName -> UnhideNames -> Bool
    unhideFilter _ (Unhide []) = False
    unhideFilter name (Unhide us) = any (\sel -> matchName name sel) us
    matchName :: LoggerName -> NameSelector -> Bool
    matchName name (Exact name') = name == name'
    matchName name (StartsWith prefix) = T.isPrefixOf prefix name
    matchName name (EndsWith postfix) = T.isSuffixOf postfix name
    matchName name (Contains name') = T.isInfixOf name' name
\end{code}

\subsubsection{Concrete Trace on stdout}\label{code:stdoutTrace}\index{stdoutTrace}

This function returns a trace with an action of type "|(LogNamed LogObject) -> IO ()|"
which will output a text message as text and all others as JSON encoded representation
to the console.

\todo[inline]{TODO remove |locallock|}
%if style == newcode
\begin{code}
{-# NOINLINE locallock #-}
\end{code}
%endif
\begin{code}
locallock :: MVar ()
locallock = unsafePerformIO $ newMVar ()
\end{code}

\begin{code}
stdoutTrace :: TraceNamed IO
stdoutTrace = BaseTrace.BaseTrace $ Op $ \(LogNamed logname (LogObject _ lc)) ->
    withMVar locallock $ \_ ->
        case lc of
            (LogMessage logItem) ->
                    output logname $ liPayload logItem
            obj ->
                    output logname $ toStrict (encodeToLazyText obj)
  where
    output nm msg = TIO.putStrLn $ nm <> " :: " <> msg

\end{code}


\subsubsection{Concrete Trace into a |TVar|}\label{code:traceInTVar}\label{code:traceInTVarIO}\index{traceInTVar}\index{traceInTVarIO}\label{code:traceNamedInTVarIO}\index{traceNamedInTVarIO}

\begin{code}
traceInTVar :: STM.TVar [a] -> BaseTrace.BaseTrace STM.STM a
traceInTVar tvar = BaseTrace.BaseTrace $ Op $ \a -> STM.modifyTVar tvar ((:) a)

traceInTVarIO :: STM.TVar [LogObject] -> TraceNamed IO
traceInTVarIO tvar = BaseTrace.BaseTrace $ Op $ \ln ->
                         STM.atomically $ STM.modifyTVar tvar ((:) (lnItem ln))

traceNamedInTVarIO :: STM.TVar [LogNamed LogObject] -> TraceNamed IO
traceNamedInTVarIO tvar = BaseTrace.BaseTrace $ Op $ \ln ->
                         STM.atomically $ STM.modifyTVar tvar ((:) ln)

traceInTVarIOConditionally :: STM.TVar [LogObject] -> TraceContext -> TraceNamed IO
traceInTVarIOConditionally tvar ctx =
    BaseTrace.BaseTrace $ Op $ \item@(LogNamed loggername (LogObject meta _)) -> do
        globminsev  <- Config.minSeverity (configuration ctx)
        globnamesev <- Config.inspectSeverity (configuration ctx) loggername
        let minsev = max globminsev $ fromMaybe Debug globnamesev
        if (severity meta) >= minsev
        then STM.atomically $ STM.modifyTVar tvar ((:) (lnItem item))
        else return ()

traceNamedInTVarIOConditionally :: STM.TVar [LogNamed LogObject] -> TraceContext -> TraceNamed IO
traceNamedInTVarIOConditionally tvar ctx =
    BaseTrace.BaseTrace $ Op $ \item@(LogNamed loggername (LogObject meta _)) -> do
        globminsev  <- Config.minSeverity (configuration ctx)
        globnamesev <- Config.inspectSeverity (configuration ctx) loggername
        let minsev = max globminsev $ fromMaybe Debug globnamesev
        if (severity meta) >= minsev
        then STM.atomically $ STM.modifyTVar tvar ((:) item)
        else return ()

\end{code}

\subsubsection{Enter message into a trace}\label{code:traceNamedItem}\index{traceNamedItem}
The function |traceNamedItem| creates a |LogObject| and threads this through
the action defined in the |Trace|.

\begin{code}
traceNamedItem
    :: MonadIO m
    => Trace m
    -> LogSelection
    -> Severity
    -> T.Text
    -> m ()
traceNamedItem trace p s m =
    traceNamedObject trace =<<
        LogObject <$> liftIO (mkLOMeta s)
                  <*> pure (LogMessage LogItem { liSelection = p
                                               , liPayload   = m
                                               })

\end{code}

\subsubsection{Logging functions}
\label{code:logDebug}\index{logDebug}
\label{code:logDebugS}\index{logDebugS}
\label{code:logInfo}\index{logInfo}
\label{code:logInfoS}\index{logInfoS}
\label{code:logNotice}\index{logNotice}
\label{code:logNoticeS}\index{logNoticeS}
\label{code:logWarning}\index{logWarning}
\label{code:logWarningS}\index{logWarningS}
\label{code:logError}\index{logError}
\label{code:logErrorS}\index{logErrorS}
\label{code:logCritical}\index{logCritical}
\label{code:logCriticalS}\index{logCriticalS}
\label{code:logAlert}\index{logAlert}
\label{code:logAlertS}\index{logAlertS}
\label{code:logEmergency}\index{logEmergency}
\label{code:logEmergencyS}\index{logEmergencyS}
\begin{code}
logDebug, logInfo, logNotice, logWarning, logError, logCritical, logAlert, logEmergency
    :: MonadIO m => Trace m -> T.Text -> m ()
logDebug     logTrace = traceNamedItem logTrace Both Debug
logInfo      logTrace = traceNamedItem logTrace Both Info
logNotice    logTrace = traceNamedItem logTrace Both Notice
logWarning   logTrace = traceNamedItem logTrace Both Warning
logError     logTrace = traceNamedItem logTrace Both Error
logCritical  logTrace = traceNamedItem logTrace Both Critical
logAlert     logTrace = traceNamedItem logTrace Both Alert
logEmergency logTrace = traceNamedItem logTrace Both Emergency

logDebugS, logInfoS, logNoticeS, logWarningS, logErrorS, logCriticalS, logAlertS, logEmergencyS
    :: MonadIO m => Trace m -> T.Text -> m ()
logDebugS     logTrace = traceNamedItem logTrace Private Debug
logInfoS      logTrace = traceNamedItem logTrace Private Info
logNoticeS    logTrace = traceNamedItem logTrace Private Notice
logWarningS   logTrace = traceNamedItem logTrace Private Warning
logErrorS     logTrace = traceNamedItem logTrace Private Error
logCriticalS  logTrace = traceNamedItem logTrace Private Critical
logAlertS     logTrace = traceNamedItem logTrace Private Alert
logEmergencyS logTrace = traceNamedItem logTrace Private Emergency

\end{code}

\subsubsection{subTrace}\label{code:subTrace}\index{subTrace}
Transforms the input |Trace| according to the
|Configuration| using the logger name of the
current |Trace| appended with the new name. If the
empty |Text| is passed, then the logger name
remains untouched.
\begin{code}
subTrace :: MonadIO m => T.Text -> Trace m -> m (Trace m)
subTrace name tr@(ctx, _) = do
    let cfg = configuration ctx
    subtrace0 <- liftIO $ Config.findSubTrace cfg name
    let subtrace = case subtrace0 of Nothing -> Neutral; Just str -> str
    case subtrace of
        Neutral           -> do
                                (ctx',tr') <- appendName name tr
                                return $ updateTracetype subtrace (ctx', tr')
        UntimedTrace      -> do
                                (ctx',tr') <- appendName name tr
                                return $ updateTracetype subtrace (ctx', tr')
        TeeTrace _        -> do
                                (ctx',tr') <- appendName name tr
                                return $ updateTracetype subtrace (ctx', tr')
        FilterTrace _     -> do
                                tr' <- appendName name tr
                                return $ updateTracetype subtrace tr'
        NoTrace           -> return $ updateTracetype subtrace (ctx, BaseTrace.noTrace)
        DropOpening       -> return $ updateTracetype subtrace (ctx, BaseTrace.BaseTrace $ Op $
                                \(LogNamed _ lo@(LogObject _ lc)) -> do
                                    case lc of
                                        ObserveOpen _ -> return ()
                                        _             -> traceNamedObject tr lo )
        ObservableTrace _ -> do
                                (ctx',tr') <- appendName name tr
                                return $ updateTracetype subtrace (ctx', tr')

\end{code}
