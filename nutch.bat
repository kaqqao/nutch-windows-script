@echo off
setlocal
    
if "%1"=="" (
  echo Usage: nutch COMMAND
  echo where COMMAND is one of:
  echo   readdb            read / dump crawl db
  echo   mergedb           merge crawldb-s, with optional filtering
  echo   readlinkdb        read / dump link db
  echo   inject            inject new urls into the database
  echo   generate          generate new segments to fetch from crawl db
  echo   freegen           generate new segments to fetch from text files
  echo   fetch             fetch a segment's pages
  echo   parse             parse a segment's pages
  echo   readseg           read / dump segment data
  echo   mergesegs         merge several segments, with optional filtering and slicing
  echo   updatedb          update crawl db from segments after fetching
  echo   invertlinks       create a linkdb from parsed segments
  echo   mergelinkdb       merge linkdb-s, with optional filtering
  echo   index             run the plugin-based indexer on parsed segments and linkdb
  echo   dedup             deduplicate entries in the crawldb and give them a special status
  echo   solrindex         run the solr indexer on parsed segments and linkdb - DEPRECATED use the index command instead
  echo   solrdedup         remove duplicates from solr - DEPRECATED use the dedup command instead
  echo   solrclean         remove HTTP 301 and 404 documents from solr - DEPRECATED use the clean command instead
  echo   clean             remove HTTP 301 and 404 documents and duplicates from indexing backends configured via plugins
  echo   parsechecker      check the parser for a given url
  echo   indexchecker      check the indexing filters for a given url
  echo   domainstats       calculate domain statistics from crawldb
  echo   webgraph          generate a web graph from existing segments
  echo   linkrank          run a link analysis program on the generated web graph
  echo   scoreupdater      updates the crawldb with linkrank scores
  echo   nodedumper        dumps the web graph's node scores
  echo   plugin            load a plugin and run one of its classes main(^)
  echo   junit             runs the given JUnit test
  echo  or
  echo   CLASSNAME         run the class named CLASSNAME
  echo Most commands print help when invoked w/o parameters.
  exit /B 1
)

rem Check JAVA_HOME
if "%JAVA_HOME%"=="" (
	echo JAVA_HOME environment variable is not set. Program can not run.
	exit /B 1
)

rem Check NUTCH_HOME
if "%NUTCH_HOME%"=="" (
  pushd %~dp0
  cd ..
	echo WARNING: NUTCH_HOME environment variable is not set. Using %cd%.
  set NUTCH_HOME=%cd%
  popd 
)

rem Check local or deployed execution
SET NUTCH_JOB=
for %%i in ("%NUTCH_HOME%\*nutch*.job") do set NUTCH_JOB=%%i

rem check that hadoop can be found on the path 
if defined NUTCH_JOB (
	rem Set errorlevel here because of variable expansion happens before block execution
	WHERE hadoop.cmd >nul 2>&1
	IF %ERRORLEVEL% NEQ 0 (
		echo Can't find Hadoop executable. Add HADOOP_HOME/bin to the path or run in local mode.
		exit /B 1
	)
)

rem Set default paths and options
set CLASSPATH="%NUTCH_HOME%\conf";"%JAVA_HOME%\lib\tools.jar"

set NUTCH_LOG_DIR="%NUTCH_HOME%\logs"
set NUTCH_LOGFILE=hadoop.log

set NUTCH_OPTS=%NUTCH_OPTS% -Dhadoop.log.dir=%NUTCH_LOG_DIR% -Dhadoop.log.file=%NUTCH_LOGFILE%
rem -Xdebug -Xrunjdwp:transport=dt_socket,address=1317,suspend=n,server=y
set NUTCH_OPTS=-Xmx1000m -Djavax.xml.parsers.DocumentBuilderFactory=com.sun.org.apache.xerces.internal.jaxp.DocumentBuilderFactoryImpl %NUTCH_OPTS%
echo Using Nutch opts: %NUTCH_OPTS%

rem Add everything from lib to classpath
set CLASSPATH=%CLASSPATH%;"%NUTCH_HOME%\lib\*"

rem Add hadoop utils for outlinkmeta plugin for the reduce step
set CLASSPATH=%CLASSPATH%;

rem Determine the Java class to trigger
if "%1" == "crawl" (
    echo Command %1 is deprecated, please use bin/crawl instead
    exit /B 1
) else if "%1" == "inject" (
    set CLASS=org.apache.nutch.crawl.Injector
) else if "%1" == "generate" (
    set CLASS=org.apache.nutch.crawl.Generator
) else if "%1" == "freegen" (
    set CLASS=org.apache.nutch.tools.FreeGenerator
) else if "%1" == "fetch" (
    set CLASS=org.apache.nutch.fetcher.Fetcher
) else if "%1" == "parse" (
    set CLASS=org.apache.nutch.parse.ParseSegment
) else if "%1" == "readdb" (
    set CLASS=org.apache.nutch.crawl.CrawlDbReader
) else if "%1" == "mergedb" (
    set CLASS=org.apache.nutch.crawl.CrawlDbMerger
) else if "%1" == "readlinkdb" (
    set CLASS=org.apache.nutch.crawl.LinkDbReader
) else if "%1" == "readseg" (
    set CLASS=org.apache.nutch.segment.SegmentReader
) else if "%1" == "mergesegs" (
    set CLASS=org.apache.nutch.segment.SegmentMerger
) else if "%1" == "updatedb" (
    set CLASS=org.apache.nutch.crawl.CrawlDb
) else if "%1" == "invertlinks" (
    set CLASS=org.apache.nutch.crawl.LinkDb
) else if "%1" == "mergelinkdb" (
    set CLASS=org.apache.nutch.crawl.LinkDbMerger
) else if "%1" == "solrindex" (
    set CLASS=org.apache.nutch.indexer.IndexingJob -D solr.server.url=%2
    shift
) else if "%1" == "index" (
    set CLASS=org.apache.nutch.indexer.IndexingJob
) else if "%1" == "solrdedup" (
    echo Command %1 is deprecated, please use dedup instead
    exit /B 1
) else if "%1" == "dedup" (
    set CLASS=org.apache.nutch.crawl.DeduplicationJob
) else if "%1" == "solrclean" (
    set CLASS=org.apache.nutch.indexer.CleaningJob -D solr.server.url=%3 %2
    shift
    shift
) else if "%1" == "clean" (
    set CLASS=org.apache.nutch.indexer.CleaningJob
) else if "%1" == "parsechecker" (
    set CLASS=org.apache.nutch.parse.ParserChecker
) else if "%1" == "indexchecker" (
    set CLASS=org.apache.nutch.indexer.IndexingFiltersChecker
) else if "%1" == "domainstats" (
    set CLASS=org.apache.nutch.util.domain.DomainStatistics
) else if "%1" == "webgraph" (
    set CLASS=org.apache.nutch.scoring.webgraph.WebGraph
) else if "%1" == "linkrank" (
    set CLASS=org.apache.nutch.scoring.webgraph.LinkRank
) else if "%1" == "scoreupdater" (
    set CLASS=org.apache.nutch.scoring.webgraph.ScoreUpdater
) else if "%1" == "nodedumper" (
    set CLASS=org.apache.nutch.scoring.webgraph.NodeDumper
) else if "%1" == "plugin" (
    set CLASS=org.apache.nutch.plugin.PluginRepository
) else if "%1" == "junit" (
    set CLASSPATH=%CLASSPATH%:%NUTCH_HOME%/test/classes/
    set CLASS=junit.textui.TestRunner
) else (
    set CLASS=%1
)

rem Calculate the command line parameters to forward to Java
set PARAMS=
shift
:loop
if "%~1"=="" goto after_loop
rem Parameters are split on spaces *and* equal signs expect if contained in double quotes.
rem Remove the double quotes from parameters that do not contain spaces.
rem This is important for the crawl script where the solr url is given as -D solr.server.url=http://example.org
rem an must be quoted as -D "solr.server.url=http://example.org" or "-Dsolr.server.url=http://example.org" (without space).
for /F "tokens=1*" %%i in ("%~1") do set SPACE=%%j
if defined SPACE (set PARAMS=%PARAMS% %1) else (set PARAMS=%PARAMS% %~1)
shift
goto loop
:after_loop

if DEFINED NUTCH_JOB ( 
    SET EXEC_CALL=hadoop jar %NUTCH_JOB%
) else (
    SET EXEC_CALL=java %NUTCH_OPTS% -classpath %CLASSPATH%
)
call %EXEC_CALL% %CLASS% %PARAMS%
