![cover](https://github.com/hfleitas/SentimentPrediction/blob/master/Cover.png "cover")

## Resources 🐱‍🚀
1. [fleitasarts.com](http://fleitasarts.com)
2. [ailab.microsoft.com](https://ailab.microsoft.com)
3. SQL Server R Services Samples: [Microsoft Repo](https://github.com/Microsoft/SQL-Server-R-Services-Samples)
4. Pre-Trained ML Models: [Install in SQL Server](https://docs.microsoft.com/sql/advanced-analytics/r/install-pretrained-models-sql-server)
5. SQL Server Machine Learning Services: [Tutorials](http://aka.ms/mlsqldev)
6. SQL Server Components to Support Python: [Interaction of Components](https://docs.microsoft.com/sql/advanced-analytics/python/new-components-in-sql-server-to-support-python-integration?view=sql-server-2017)
7. hreading ML: [Logistic Regression](https://docs.microsoft.com/machine-learning-server/python-reference/microsoftml/rx-logistic-regression)
8. Resource Governor: [Alter External Resource Pool](https://docs.microsoft.com/sql/advanced-analytics/r/how-to-create-a-resource-pool-for-r?view=sql-server-2017)
9. Interactive deep learning: [Learn alert](https://aka.ms/AA3dz6b)
10. [aka.ms/sqlworkshops](https://aka.ms/sqlworkshops)
11. [aka.ms/ss19](https://aka.ms/ss19)

# Sentiment Prediction
### Real-time in SQL Server
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

To restore see file: [SQLServerScripts.sql](https://github.com/hfleitas/SentimentPrediction/blob/master/SQL/SQLServerScripts.sql)

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

1. Enable external scripts by running [SQLServerScripts.sql](https://github.com/hfleitas/SentimentPrediction/blob/master/SQL/SQLServerScripts.sql) on your SQL Server instance. Be aware Reconfigure with Override will immediatly apply any modified config values to the running config.
```
EXEC sp_configure 'external scripts enabled', 1
RECONFIGURE WITH OVERRIDE
go
```

2. Walk through the steps in [SQLServerScripts.sql](https://github.com/hfleitas/SentimentPrediction/blob/master/SQL/SQLServerScripts.sql) to see how Sentiment Analysis works inside the datase.

3. You may Start without Debugging [GetSentimentExample.py](https://github.com/hfleitas/SentimentPrediction/blob/master/Python/Example1.py), in Visual Studio 2017 Community Edition, get the Tools/Features for Python, then  set the Python Envirments to SQLServer2019ctp2 or SQLServer2017PythonSvcs, whichever version of SQL Server you have installed. The prefix path for the Python Enviroment will be like so [C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\PYTHON_SERVICES], click Auto Detect, Apply and set this as the default enviroment. 

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
* Code in Python and T-SQL (sp_execute_external_script)
* Python Profiling
* Real-time scoring
* Azure Data Studio Notebooks
* Cognitive API (Text Analytics)

The intention is to process large amounts of inputs and predict quality scores fast enough for real-time operations. It's advisable to monitor the system task manager cpu/ram during the train model step(s). 

## Deployment

You may clone this repo and open it in [Azure Data Studio](https://docs.microsoft.com/sql/azure-data-studio/download) or open the solution file [SentimentML.sln] in Visual Studio.

Follow instructions in [SQLServerScripts.sql](https://github.com/hfleitas/SentimentPrediction/blob/master/SQL/SQLServerScripts.sql).

## Built With

* [SQL Server 2017 and up](https://aka.ms/sqlserver) - The #1 database engine in the world.

## Contributing

Please read [CONTRIBUTING.md](https://github.com/hfleitas/SentimentPrediction) for code of conduct, and the process for submitting pull requests.

## Versioning

I use [Github](http://github.com/) for versioning. For the versions available, see the [tags on this repository](https://github.com/hfleitas/SentimentPrediction/tags). 

## Authors

* **Hiram Fleitas** - *This Repo - SentimentPrediction* - [Hiram Fleitas](https://github.com/hfleitas)

See also the list of [contributors](https://github.com/hfleitas/SentimentPrediction/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

* [Nellie Gustafsson](https://github.com/NelGson) - Senior Program Manager (Microsoft)
* [Sumit Kumar](https://github.com/sumitkmsft) - Principal Product Manager (Microsoft)
* [Ryan Donaghy](https://github.com/gh-canon) - Senior Software Developer (Universal Property)
* MS Research and the entire SQL Server ML team.
