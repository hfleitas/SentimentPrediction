# GetSentimentExample
Python and T-SQL solution for Sentiment analysis and Real-time predictions in SQL Server 2017+

## Getting Started

This example should work on any machine running SQL Server 2017.

It assumes you have restored the tpcxbb_1gb sample database on a SQL Server 2017 instance. If not, just follow the instructions.

Get Sentiment Example: (requirements: SQL Server 2017+, Machine Learning Services (In-Database) R & Python, tpcxbb_1gb)

tpcxbb_1gb db (see latest release tpcxbb_1gb.bak [234 MB]): https://sqlchoice.blob.core.windows.net/sqlchoice/static/tpcxbb_1gb.bak

### Prerequisites

Powershell/Cmd, SQL Server 2017, Machine Learning Services (In-Database) R & Python, tpcxbb_1gb database.

### Installing

Install SQL Server 2017+ on your local machine. I recommend choosing Developer Edition for the purpose of this example:  https://www.microsoft.com/en-us/sql-server/sql-server-downloads

Select to Add Feature Machine Learning Services (In-Database), R and Python.

Download latest release [tpcxbb_1gb.bak [234 MB]](https://sqlchoice.blob.core.windows.net/sqlchoice/static/tpcxbb_1gb.bak) and restore it. (If you already have you may skip this step)

To restore see file: [SQLServerScripts.sql](https://github.com/hfleitas/GetSentimentExample/blob/master/GetSentimentExample/SQLServerScripts.sql)

```
--verify
restore filelistonly from disk = 'c:\users\hfleitas\downloads\tpcxbb_1gb.bak'
go 
--set your own paths
restore database [tpcxbb_1gb] from disk = 'c:\users\hfleitas\downloads\tpcxbb_1gb.bak' with replace,
move 'tpcxbb_1gb' to 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\tpcxbb_1gb.mdf', 
move 'tpcxbb_1gb_log' to 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\tpcxbb_1gb.ldf'
go
--rollup compat to 140 for 2017 or 150 for 2019
alter database [tpcxbb_1gb] set COMPATIBILITY_LEVEL = 150 --2019
go
--update stats (you may skip this step)
use [tpcxbb_1gb]
go
EXEC sp_updatestats
```

1. Enable external scripts by running [SQLServerScripts.sql](https://github.com/hfleitas/GetSentimentExample/blob/master/GetSentimentExample/SQLServerScripts.sql) on your SQL Server instance. Be aware Reconfigure with Override will immediatly apply any modified config values to the running config.
```
EXEC sp_configure 'external scripts enabled', 1
RECONFIGURE WITH OVERRIDE
go
```

2. Walk through the steps in [SQLServerScripts.sql](https://github.com/hfleitas/GetSentimentExample/blob/master/GetSentimentExample/SQLServerScripts.sql) to see how Sentiment Analysis works inside the datase.

3. You may Start without Debugging [GetSentimentExample.py](https://github.com/hfleitas/GetSentimentExample/blob/master/GetSentimentExample/GetSentimentExample.py), in Visual Studio 2017 Community Edition, get the Tools/Features for Python, then  set the Python Envirments to SQLServer2019ctp2 or SQLServer2017PythonSvcs, whichever version of SQL Server you have installed. The prefix path for the Python Enviroment will be like so [C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\PYTHON_SERVICES], click Auto Detect, Apply and set this as the default enviroment. 

End with sp_rxPredict:

```
exec sp_rxPredict @model = @model_bin, @inputData = N'SELECT pr_review_content, cast(tag as varchar(1)) as tag FROM product_reviews_test_data' end;
```

### Purpose

This example will illustrate how to:
* Add ML Features
* Grant Access
* Config
* Install Pre-Trained & Open Source ML Models (Deep Neural Networks)
* Code in Python and T-SQL
* Python Profiling
* Real-time scoring

The intention is to process large amounts of inputs and predict quality scores fast enough for real-time operations. It's advisable to monitor the system task manager cpu/ram during the train model step(s). 

## Deployment

You may download this repo and open the solution file [GetSentimentExample.sln] in Visual Studio.

Follow instructions in [SQLServerScripts.sql](https://github.com/hfleitas/GetSentimentExample/blob/master/GetSentimentExample/SQLServerScripts.sql).

## Built With

* [SQL Server 2017](https://www.microsoft.com/en-us/sql-server/sql-server-downloads) - The #1 database engine in the world.

## Contributing

Please read [CONTRIBUTING.md](https://github.com/hfleitas/GetSentimentExample) for code of conduct, and the process for submitting pull requests.

## Versioning

I use [Github](http://github.com/) for versioning. For the versions available, see the [tags on this repository](https://github.com/hfleitas/GetSentimentExample/tags). 

## Authors

* **Hiram Fleitas** - *This Repo - GetSentimentExample* - [Hiram Fleitas](https://github.com/hfleitas)

See also the list of [contributors](https://github.com/hfleitas/GetSentimentExample/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

* [Nellie Gustafsson](https://github.com/NelGson) - Program Manager (Microsoft)
* MS Research and the entire SQL Server ML team.
