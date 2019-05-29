rem Fix for long path error with SQL Server 2017 CU6 Python ML Win Svr 930.
rem run as admin cmd.

rem see working dir in : C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\Binn\pythonlauncher.config
rem bad: WORKING_DIRECTORY=C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\ExtensibilityData
rem good: WORKING_DIRECTORY=C:\SQL-MSSQLSERVER-ExtensibilityData-PY

cd "C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\PYTHON_SERVICES\Lib\site-packages\revoscalepy\rxLibs\"

rem uninstall
registerRext.exe /uninstall /sqlbinnpath:"C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\PYTHON_SERVICES\..\MSSQL\Binn" /userpoolsize:0 /instance:"MSSQLSERVER" /python
 
rem install
registerRext.exe /install /sqlbinnpath:"C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\PYTHON_SERVICES\..\MSSQL\Binn" /userpoolsize:0 /instance:"MSSQLSERVER" /python
