@echo off
rem
rem Licensed to the Apache Software Foundation (ASF) under one or more
rem contributor license agreements.  See the NOTICE file distributed with
rem this work for additional information regarding copyright ownership.
rem The ASF licenses this file to You under the Apache License, Version 2.0
rem (the "License"); you may not use this file except in compliance with
rem the License.  You may obtain a copy of the License at
rem
rem     http://www.apache.org/licenses/LICENSE-2.0
rem
rem Unless required by applicable law or agreed to in writing, software
rem distributed under the License is distributed on an "AS IS" BASIS,
rem WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
rem See the License for the specific language governing permissions and
rem limitations under the License.
rem 
rem The Crawl command script : crawl <seedDir> <crawlDir> <solrURL> <numberOfRounds>
rem
rem 
rem UNLIKE THE NUTCH ALL-IN-ONE-CRAWL COMMAND THIS SCRIPT DOES THE LINK INVERSION AND 
rem INDEXING FOR EACH SEGMENT

setlocal
set SEEDDIR=%~1
set CRAWL_PATH=%~2
set SOLRURL=%3
set LIMIT=%4

set NUTCH_OPTS_ENV=%NUTCH_OPTS%

if "%SEEDDIR%" == "" ( 
    echo Missing seedDir : crawl ^<seedDir^> ^<crawlDir^> ^<solrURL^> ^<numberOfRounds^>
    exit /B 1;
)

if "%CRAWL_PATH%" == "" (
    echo Missing crawlDir : crawl ^<seedDir^> ^<crawlDir^> ^<solrURL^> ^<numberOfRounds^>
    exit /B 1;
)

if "%SOLRURL%" == "" (
    echo Missing SOLRURL : crawl ^<seedDir^> ^<crawlDir^> ^<solrURL^> ^<numberOfRounds^>
    exit /B 1;
)

if "%LIMIT%" == "" (
    echo Missing numberOfRounds : crawl ^<seedDir^> ^<crawlDir^> ^<solrURL^> ^<numberOfRounds^>
    exit /B 1;
)

rem #############################################
rem # MODIFY THE PARAMETERS BELOW TO YOUR NEEDS #
rem #############################################

rem set the number of slaves nodes
set numSlaves=1

rem and the total number of available tasks
rem sets Hadoop parameter "mapred.reduce.tasks"
set /a numTasks=%numSlaves% * 2

rem number of urls to fetch in one iteration
rem 250K per task?
set /a sizeFetchlist=%numSlaves% * 50000

rem time limit for feching
set timeLimitFetch=180

rem num threads for fetching
set numThreads=50

echo numSlaves=%numSlaves%
echo numTasks=%numTasks%
echo sizeFetchlist=%sizeFetchlist%
echo timeLimitFetch=%timeLimitFetch%
echo numThreads=%numThreads%

rem #############################################

rem determines whether mode based on presence of job file
set NUTCH_JOB=
for %%i in ("%NUTCH_HOME%\*nutch*.job") do set NUTCH_JOB=%%i

SET BIN=%~dp0

rem note that some of the options listed here could be set in the 
rem corresponding hadoop site xml param file 
SET commonOptions=-Dmapred.reduce.tasks=%numTasks% -Dmapred.child.java.opts=-Xmx1000m -Dmapred.reduce.tasks.speculative.execution=false -Dmapred.map.tasks.speculative.execution=false -Dmapred.compress.map.output=true

rem check that hadoop can be found on the path 
if defined NUTCH_JOB (
	rem Set errorlevel here because of variable expansion happens before block execution
	WHERE hadoop.cmd >nul 2>&1
	IF %ERRORLEVEL% NEQ 0 (
		echo Can't find Hadoop executable. Add HADOOP_HOME/bin to the path or run in local mode.
		exit /B 1
	)
)

rem initial injection
SET NUTCH_OPTS=%NUTCH_OPTS_ENV%
rem call %bin%nutch.bat inject "%CRAWL_PATH%/crawldb" "%SEEDDIR%"

if %ERRORLEVEL% NEQ 0 (
	exit /B %ERRORLEVEL% 
)

rem main loop : rounds of generate - fetch - parse - update
setlocal ENABLEDELAYEDEXPANSION
for /L %%i IN (1,1,%LIMIT%) do (

	if exist *.STOP (
		echo STOP file found - escaping loop
		goto break
	)

	echo %DATE% %TIME% : Iteration %%i of %LIMIT%

	echo Generating a new segment
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV% %commonOptions%
	rem call %bin%nutch.bat generate "%CRAWL_PATH%/crawldb" "%CRAWL_PATH%/segments" -topN %sizeFetchlist% -numFetchers %numSlaves% -noFilter
  
	if %ERRORLEVEL% NEQ 0 (
		exit /B %ERRORLEVEL% 
	)

	rem capture the name of the segment
	rem call hadoop in distributed mode
	rem or use ls

	SET SEGMENT=

	if not defined NUTCH_JOB (
		rem alternatively, the creation date can be used: /O-D /TC instead of /O-N
		rem by using double quotes around the path it is allowed to contain forward slashes
		for /F %%s IN ('dir "%CRAWL_PATH%\segments" /O-N /AD /B') do (
			if not defined SEGMENT (
				set SEGMENT=%%s
			)
		)
	) else (
		rem not yet rewritten for hdfs usage on windows
		echo Not yet rewritten for hdfs usage on windows, stopping ...
		exit /B 1
		rem set SEGMENT=`hadoop fs -ls %CRAWL_PATH%/segments/ | grep segments |  sed -e "s/\//\\n/g" | egrep 20[0-9]+ | sort -n | tail -n 1`
		for /F %%s IN ('hdfs dfs -ls %CRAWL_PATH%/segments/' ^| findstr "segments/") do (
			if not defined SEGMENT (
				set SEGMENT=%%s
			)
		)
	)

	echo Operating on segment : !SEGMENT!
goto break
	rem fetching the segment
	echo Fetching : !SEGMENT!
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV% %commonOptions% -Dfetcher.timelimit.mins=%timeLimitFetch%
	call %bin%nutch fetch "%CRAWL_PATH%/segments/!SEGMENT!" -noParsing -threads %numThreads%

	if %ERRORLEVEL% NEQ 0 (
		exit /B %ERRORLEVEL% 
	)

	rem parsing the segment
	echo Parsing : !SEGMENT!
	rem enable the skipping of records for the parsing so that a dodgy document 
	rem so that it does not fail the full task
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV% %commonOptions% -Dmapred.skip.attempts.to.start.skipping=2 -Dmapred.skip.map.max.skip.records=1
	call %bin%nutch parse "%CRAWL_PATH%/segments/!SEGMENT!"

	if %ERRORLEVEL% NEQ 0 (
		exit /B %ERRORLEVEL% 
	)

	rem updatedb with this segment
	echo CrawlDB update
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV% %commonOptions%
	call %bin%nutch updatedb "%CRAWL_PATH%/crawldb"  "%CRAWL_PATH%/segments/!SEGMENT!"

	if %ERRORLEVEL% NEQ 0 (
		exit /B %ERRORLEVEL% 
	)

	rem note that the link inversion - indexing routine can be done within the main loop 
	rem on a per segment basis
	echo Link inversion
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV%
	call %bin%nutch invertlinks "%CRAWL_PATH%/linkdb" "%CRAWL_PATH%/segments/!SEGMENT!"

	if %ERRORLEVEL% NEQ 0 (
		exit /B %ERRORLEVEL% 
	)

	echo Dedup on crawldb
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV%
	call %bin%nutch dedup "%CRAWL_PATH%/crawldb"
  
	if %ERRORLEVEL% NEQ 0 (
		exit /B %ERRORLEVEL% 
	)

	rem echo Indexing !SEGMENT! on SOLR index -^> %SOLRURL%
	rem SET NUTCH_OPTS=%NUTCH_OPTS_ENV% -Dsolr.server.url=%SOLRURL%
	rem %bin%nutch index "%CRAWL_PATH%/crawldb" -linkdb "%CRAWL_PATH%/linkdb" "%CRAWL_PATH%/segments/!SEGMENT!"
	
	echo Sending !SEGMENT! to EUCases web service -^> %SOLRURL%
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV% -Deucasesindexer.serviceUrl=%SOLRURL%
	call %bin%nutch index "%CRAWL_PATH%/crawldb" -linkdb "%CRAWL_PATH%/linkdb" "%CRAWL_PATH%/segments/!SEGMENT!"
  
	if %ERRORLEVEL% NEQ 0 (
		exit /B %ERRORLEVEL% 
	)

	rem echo Cleanup on SOLR index -^> %SOLRURL%
	rem SET NUTCH_OPTS=%NUTCH_OPTS_ENV% -Dsolr.server.url=%SOLRURL%
	rem call %bin%nutch clean "%CRAWL_PATH%/crawldb"
	
	echo Cleanup on EUCases web service -^> %SOLRURL%
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV% -Deucasesindexer.serviceUrl=%SOLRURL%
	call %bin%nutch clean "%CRAWL_PATH%/crawldb"
  
	if %ERRORLEVEL% NEQ 0 (
		exit /B %ERRORLEVEL% 
	)

)
endlocal

:break
	SET NUTCH_OPTS=%NUTCH_OPTS_ENV%
	call "%bin%nutch" index "-Deucasesindexer.serviceUrl=%SOLRURL%" "%CRAWL_PATH%/crawldb" -linkdb "%CRAWL_PATH%/linkdb" "%CRAWL_PATH%/segments/!SEGMENT!"

exit /B 0
