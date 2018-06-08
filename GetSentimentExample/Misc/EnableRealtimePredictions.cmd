rem https://docs.microsoft.com/en-us/sql/advanced-analytics/r/how-to-do-realtime-scoring?view=sql-server-2017#bkmk_enableRtScoring
rem run cmd as admin

cd "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\R_SERVICES\library\RevoScaleR\rxLibs\x64\"
RegisterRExt.exe /installRts /database:tpcxbb_1gb