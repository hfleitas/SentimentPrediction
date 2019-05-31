-- https://docs.microsoft.com/en-us/sql/advanced-analytics/data-collection-ml-troubleshooting-process?view=sql-server-2017
set nocount on;
exec sp_execute_external_script @language = N'R', @script = N'
# Transform R version properties to data.frame
OutputDataSet <- data.frame( property_name = c("R.version", "Revo.version"), 
  property_value = c(R.Version()$version.string, Revo.version$version.string), stringsAsFactors = FALSE )
# Retrieve properties like R.home, libPath & default packages
OutputDataSet <- rbind( OutputDataSet, data.frame( property_name = c("R.home", "libPaths", "defaultPackages"),
  property_value = c(R.home(), .libPaths(), paste(getOption("defaultPackages"), collapse=", ")), stringsAsFactors = FALSE) )'
WITH RESULT SETS ((PropertyName nvarchar(100), PropertyValue nvarchar(4000)));
go
-- Get Python runtime properties:
exec sp_execute_external_script @language = N'Python', @script = N'
import sys
import pkg_resources
OutputDataSet = pandas.DataFrame( {"property_name": ["Python.home", "Python.version", "Revo.version", "MML.version", "libpaths"],
	"property_value": [sys.executable[:-10], sys.version, pkg_resources.get_distribution("revoscalepy").version, pkg_resources.get_distribution("microsoftml").version, str(sys.path)]} )'
WITH RESULT SETS ((PropertyName nvarchar(100), PropertyValue nvarchar(4000)));
go
-- See msgs tab Python revoscalepy and mml versions.
EXEC sp_execute_external_script @language =N'Python',
@script=N'
import sys, revoscalepy, microsoftml
print(sys.version)
print(revoscalepy.__version__)
print(microsoftml.__version__)',
@input_data_1 =N'select 1'
WITH RESULT SETS NONE;
GO
/*STDOUT message(s) from external script: 
3.5.2 |Continuum Analytics, Inc.| (default, Jul  5 2016, 11:41:13) [MSC v.1900 64 bit (AMD64)]
9.2.0
1.4.0.1375
*/