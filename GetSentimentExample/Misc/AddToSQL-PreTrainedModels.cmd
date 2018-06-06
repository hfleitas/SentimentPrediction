rem Run cmd as admininistrator.
rem Ref: https://docs.microsoft.com/sql/advanced-analytics/r/install-pretrained-models-sql-server

cd C:\Program Files\Microsoft SQL Server\140\Setup Bootstrap\SQL2017\x64\
RSetup.exe /install /component MLM /version 9.2.0.24 /language 1033 /destdir "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\PYTHON_SERVICES\Lib\site-packages\microsoftml\mxLibs"


rem RSetup.exe /install /component MLM /version 9.2.0.24 /language 1033 /destdir "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\PYTHON_SERVICES"
