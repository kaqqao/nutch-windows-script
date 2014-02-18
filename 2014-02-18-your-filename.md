@echo off

echo %CD%

rem Check JAVA_HOME
if "%JAVA_HOME%"=="" (
	echo JAVA_HOME environment variable is not set. Program can not run.
	exit /B 1
)

rem Check NUTCH_HOME
if "%NUTCH_HOME%"=="" (
	echo WARNING: NUTCH_HOME environment variable is not set. Using the current directory.
	set NUTCH_HOME=.
)

rem Set default paths and options
set CLASSPATH="%NUTCH_HOME%\conf";"%JAVA_HOME%\lib\tools.jar"

set NUTCH_LOG_DIR="%NUTCH_HOME%\logs"
set NUTCH_LOGFILE=hadoop.log

set NUTCH_OPTS=-Dhadoop.log.dir=%NUTCH_LOG_DIR% -Dhadoop.log.file=%NUTCH_LOGFILE%
rem -Xdebug -Xrunjdwp:transport=dt_socket,address=1317,suspend=n,server=y
set NUTCH_OPTS=-Xmx1000m -Djavax.xml.parsers.DocumentBuilderFactory=com.sun.org.apache.xerces.internal.jaxp.DocumentBuilderFactoryImpl %NUTCH_OPTS%
echo Using Nutch opts: %NUTCH_OPTS%

rem Add everything from lib to classpath
set CLASSPATH=%CLASSPATH%;"%NUTCH_HOME%\lib\*"

rem Determine the Java class to trigger
if "%1" == "crawl" (
	set CLASS=org.apache.nutch.crawl.Crawler
) else if "%1" == "solrindex" (
	set CLASS=org.apache.nutch.indexer.solr.SolrIndexerJob
)

rem Calculate the command line parameters to forward to Java
set PARAMS=
shift
:loop
if "%1"=="" goto after_loop
set PARAMS=%PARAMS% %1
shift
goto loop

:after_loop
java %NUTCH_OPTS% -classpath %CLASSPATH% %CLASS% %PARAMS%

