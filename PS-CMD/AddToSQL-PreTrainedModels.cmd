rem Run cmd as admininistrator.
rem Ref: https://docs.microsoft.com/sql/advanced-analytics/r/install-pretrained-models-sql-server

rem 2017
cd C:\Program Files\Microsoft SQL Server\140\Setup Bootstrap\SQL2017\x64\
RSetup.exe /install /component MLM /version 9.2.0.24 /language 1033 /destdir "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\PYTHON_SERVICES\Lib\site-packages\microsoftml\mxLibs"

rem 2019
cd C:\Program Files\Microsoft SQL Server\150\Setup Bootstrap\SQL2019RC1\x64\
RSetup.exe /install /component MLM /version 9.4.7.0 /language 1033 /destdir "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\PYTHON_SERVICES\Lib\site-packages\microsoftml\mxLibs"
