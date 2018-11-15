-- blog: https://blogs.msdn.microsoft.com/sqlserverstorageengine/2017/11/01/sentiment-analysis-with-python-in-sql-server-machine-learning-services/
-- Added train_threads=1 to [create_text_classification_model] for Memory Error in 2019ctp2. 
-- To fix "path name too long" added os.putenv("TMP", os.path.join("temp")) After import platform line in C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\PYTHON_SERVICES\Lib\site-packages\revoscalepy\__init__.py, then restarted LaunchPad svc.
--  + --------------------- +
--  | 1. restore sample db. |
--  + --------------------- +
--The database used for this sample can be downloaded here: https://sqlchoice.blob.core.windows.net/sqlchoice/static/tpcxbb_1gb.bak
restore filelistonly from disk = 'c:\users\hfleitas\downloads\tpcxbb_1gb.bak'
go
restore database [tpcxbb_1gb] from disk = 'c:\users\hfleitas\downloads\tpcxbb_1gb.bak' with replace,
move 'tpcxbb_1gb' to 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\tpcxbb_1gb.mdf', 
move 'tpcxbb_1gb_log' to 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\tpcxbb_1gb.ldf'
go
waitfor delay '00:00:05'
go
alter database [tpcxbb_1gb] set COMPATIBILITY_LEVEL = 150 --2019
GO
EXEC sp_configure 'external scripts enabled', 1
RECONFIGURE WITH OVERRIDE
go
declare @sql nvarchar(max)
select @sql = N'if not exists (select 1 from syslogins where name ='''+ @@servername +'\SQLRUserGroup'')
begin
	create login ['+ @@servername +'\SQLRUserGroup] from windows
end
grant EXECUTE ANY EXTERNAL SCRIPT to ['+ @@servername +'\SQLRUserGroup];
alter server role sysadmin add member ['+ @@servername +'\SQLRUserGroup];
use tpcxbb_1gb;
if not exists (select 1 from sysusers where name ='''+ @@servername +'\SQLRUserGroup'')
begin
	create user ['+ @@servername +'\SQLRUserGroup] from login ['+ @@servername +'\SQLRUserGroup];
end
alter role db_datawriter add member ['+ @@servername +'\SQLRUserGroup]'
print @sql; exec sp_executesql @sql;
go
-- Restart SQL Service & LAUNCHPAD.
-- Run PS as admin: .\Install-MLModels.ps1 MSSQLSERVER
-- Install Latest SQL Server CU, Reboot.
-- Run CMD as admin: FixPath.cmd
-- Verify WORKING_DIRECTORY in ...\MSSQL\Binn\pythonlauncher.config 
-- Run CMD as admin: AddToSQL-PreTrainedModels.cmd. It downloads & installs the pre-trained models.

/* Other Notes*/
-- upgrade/bind instance https://docs.microsoft.com/sql/advanced-analytics/r/use-sqlbindr-exe-to-upgrade-an-instance-of-sql-server
-- install python libraries interpreter https://docs.microsoft.com/machine-learning-server/install/python-libraries-interpreter

--  + ------------------------ +
--  | 2. use pre-trained model | 
--  + ------------------------ + 
-- Create stored procedure that uses a pre-trained model to determine sentiment of a given text
use [tpcxbb_1gb]
go
CREATE OR ALTER PROCEDURE [dbo].[get_sentiment](@text NVARCHAR(MAX))
AS
BEGIN

DECLARE  @script nvarchar(max);

--The Python script we want to execute
SET @script = N'
import pandas as p
from microsoftml import rx_featurize, get_sentiment

analyze_this = text

# Create the data
text_to_analyze = p.DataFrame(data=dict(Text=[analyze_this]))

# Get the sentiment scores
sentiment_scores = rx_featurize(data=text_to_analyze,ml_transforms=[get_sentiment(cols=dict(scores="Text"))])

# Lets translate the score to something more meaningful
sentiment_scores["Sentiment"] = sentiment_scores.scores.apply(lambda score: "Positive" if score > 0.6 else "Negative")
';
 
EXECUTE sp_execute_external_script @language = N'Python'
	, @script = @script
	, @output_data_1_name = N'sentiment_scores'
	, @params = N'@text nvarchar(max)'
	, @text = @text
WITH RESULT SETS (("Text" NVARCHAR(MAX),"Score" FLOAT, "Sentiment" NVARCHAR(30)));   
END    
GO

--  + -----------------+
--  | 3. Test the proc |
--  + -----------------+
-- The below examples test a negative and a positive review text
exec [get_sentiment] N'These are not a normal stress reliever. First of all, they got sticky, hairy and dirty on the first day I received them. Second, they arrived with tiny wrinkles in their bodies and they were cold. Third, their paint started coming off. Fourth when they finally warmed up they started to stick together. Last, I thought they would be foam but, they are a sticky rubber. If these were not rubber, this review would not be so bad.';
go --0.424483060836792	Negative
exec [get_sentiment] N'These are the cutest things ever!! Super fun to play with and the best part is that it lasts for a really long time. So far these have been thrown all over the place with so many of my friends asking to borrow them because they are so fun to play with. Super soft and squishy just the perfect toy for all ages.'
go --0.869342148303986	Positive
exec [get_sentiment] N'I really did not like the taste of it' 
go --0.46178987622261	Negative
exec [get_sentiment] N'It was surprisingly quite good!'
go --0.960192441940308	Positive
exec [get_sentiment] N'I will never ever ever go to that place again!!' 
go --0.310343533754349	Negative
exec [get_sentiment] N'Destiny is a gift. Some go their entire lives, living existence as a quiet desperation. Never learning the truth that what feels as though a burden pushing down upon our shoulders, is actually, a sense of purpose that lifts us to greater heights. Never forget that fear is but the precursor to valor, that to strive and triumph in the face of fear, is what it means to be a hero. Don''t think, Master Jim. Become!'
--0.5	Negative. Why...Not enough?
-- https://azure.microsoft.com/en-us/services/cognitive-services/text-analytics/ 
-- Language: English, Sentiment: 78%.
-- Key phrases: face of fear, existence, triumph, valor, sense of purpose, entire lives, quiet desperation, shoulders, greater heights, precursor, Destiny, gift, Master Jim, burden, truth, hero. 
go

--  + ------------------------------------ +
--  | 4. create schema to train own model. |
--  + ------------------------------------ +
USE [tpcxbb_1gb]
GO
--**************************************************************
-- STEP 1 Create a table for storing the machine learning model
--**************************************************************
DROP TABLE IF EXISTS [dbo].[models]
GO
CREATE TABLE [dbo].[models](
 [language] [varchar](30) NOT NULL,
 [model_name] [varchar](30) NOT NULL,
 [model] [varbinary](max) NOT NULL,
 [create_time] [datetime2](7) NULL DEFAULT (sysdatetime()),
 [created_by] [nvarchar](500) NULL DEFAULT (suser_sname()),
 PRIMARY KEY CLUSTERED  ( [language], [model_name] )
)
GO

-- STEP 2 Look at the dataset we will use in this sample
-- Tag is a label indicating the sentiment of a review. These are actual values we will use to train the model
-- For training purposes, we will use 90% percent of the data.
-- For testing / scoring purposes, we will use 10% percent of the data.

CREATE OR ALTER VIEW product_reviews_training_data
AS
SELECT TOP(CAST( ( SELECT COUNT(*) FROM   product_reviews)*.9 AS INT))
  CAST(pr_review_content AS NVARCHAR(4000)) AS pr_review_content,
  CASE 
   WHEN pr_review_rating <3 THEN 1 
   WHEN pr_review_rating =3 THEN 2 
   ELSE 3 END AS tag 
FROM   product_reviews;
GO

CREATE OR ALTER VIEW product_reviews_test_data
AS
SELECT TOP(CAST( ( SELECT COUNT(*) FROM   product_reviews)*.1 AS INT))
  CAST(pr_review_content AS NVARCHAR(4000)) AS pr_review_content,
  CASE 
   WHEN pr_review_rating <3 THEN 1 
   WHEN pr_review_rating =3 THEN 2 
   ELSE 3 END AS tag 
FROM   product_reviews;
GO

-- STEP 3 Create a stored procedure for training a text classifier model for product review sentiment classification (Positive, Negative, Neutral)
-- 1 = Negative, 2 = Neutral, 3 = Positive
CREATE OR ALTER PROCEDURE [dbo].[create_text_classification_model]
AS
BEGIN
 DECLARE @model varbinary(max), @train_script nvarchar(max);
 --The Python script we want to execute
 SET @train_script = N'
##Import necessary packages
from microsoftml import rx_logistic_regression,featurize_text, n_gram
import pickle
## Defining the tag column as a categorical type
training_data["tag"] = training_data["tag"].astype("category")

## Create a machine learning model for multiclass text classification. 
## We are using a text featurizer function to split the text in features of 2-word chunks

#ngramLength=2: include not only "Word1", "Word2", but also "Word1 Word2"
#weighting="TfIdf": Term frequency & inverse document frequency
model = rx_logistic_regression(formula = "tag ~ features", data = training_data, method = "multiClass", ml_transforms=[
                        featurize_text(language="English",
                                     cols=dict(features="pr_review_content"),
                                      word_feature_extractor=n_gram(2, weighting="TfIdf"))],
						train_threads=1) ##Single Thread for 2019ctp2

## Serialize the model so that we can store it in a table
modelbin = pickle.dumps(model)';

 EXECUTE sp_execute_external_script
      @language = N'Python'
       , @script = @train_script
       , @input_data_1 = N'SELECT * FROM product_reviews_training_data'
       , @input_data_1_name = N'training_data'
       , @params  = N'@modelbin varbinary(max) OUTPUT' 
       , @modelbin = @model OUTPUT;
 --Save model to DB Table      
 DELETE FROM dbo.models WHERE model_name = 'rx_logistic_regression' and language = 'Python';
 INSERT INTO dbo.models (language, model_name, model) VALUES('Python', 'rx_logistic_regression', @model);
END;
GO
-- STEP 4 Execute the stored procedure that creates and saves the machine learning model in a table
EXECUTE [dbo].[create_text_classification_model];
--Take a look at the model object saved in the model table
SELECT * FROM dbo.models;
GO

-- STEP 5 --Proc that uses the model we just created to predict/classify the sentiment of product reviews
CREATE OR ALTER PROCEDURE [dbo].[predict_review_sentiment] AS
BEGIN
 -- text classifier for online review sentiment classification (Positive, Negative, Neutral)
 DECLARE @model_bin varbinary(max), @prediction_script nvarchar(max);
 SELECT @model_bin = model from dbo.models WHERE model_name = 'rx_logistic_regression' and language = 'Python';
 
 --The Python script we want to execute
 SET @prediction_script = N'
from microsoftml import rx_predict
from revoscalepy import rx_data_step 
import pickle

## The input data from the query in @input_data_1 is populated in test_data
## We are selecting 10% of the entire dataset for testing the model

## Unserialize the model
model = pickle.loads(model_bin)

## Use the rx_logistic_regression model 
predictions = rx_predict(model = model, data = test_data, extra_vars_to_write = ["pr_review_content"], overwrite = True)

## Converting to output data set
result = rx_data_step(predictions)

## print(result)';
 
 EXECUTE sp_execute_external_script
    @language = N'Python'
    , @script = @prediction_script
    , @input_data_1 = N'SELECT * FROM product_reviews_test_data'
    , @input_data_1_name = N'test_data'
    , @output_data_1_name = N'result'
    , @params  = N'@model_bin varbinary(max)'
    , @model_bin = @model_bin
  WITH RESULT SETS (("Review" NVARCHAR(MAX), "PredictedLabel" FLOAT, "Predicted_Score_Negative" FLOAT, "Predicted_Score_Neutral" FLOAT, "Predicted_Score_Positive" FLOAT)); 
END 
GO
--added PredictedLablel (seen msgs tab with print(result)).
--use print(result) to see dataframe columns to match result set columns.

-- STEP 6 Execute the multi class prediction using the model we trained earlier
-- The predicted score of Negative means the statement is (x percent Negative), and so on for the other sentiment categories. 
-- Ie. since the’re all tag 3 positive, they will have very low negative scores, low neutral scores and very high positive scores. 
EXECUTE [dbo].[predict_review_sentiment] --13sec 8999 rows.
--EXECUTE statement failed because its WITH RESULT SETS clause specified 5 column(s) for result set number 1, but the statement sent 6 column(s) at run time.
--fixed by seeing actual output using print(result) in messages tab.
go
-- STEP 7 Use TSQL PREDICT with a serialized model that uses realtimeScoring = True.
create or alter proc uspPredictSentiment 
@model varchar(30) = 'rx_logistic_regression'
as
begin
	declare @model_bin varbinary(max);
	select @model_bin = model from dbo.models where model_name = @model and language = 'Python';
	
	select	p.pr_review_content, p.score
	from	predict(model=@model_bin, data = product_reviews_test_data as d)
	with	(pr_review_content nvarchar(max), score float) as p;
end
go
exec uspPredictSentiment
-- That model is an mml model (Microsoft ML). And PREDICT does not support mml models at this time.
/*Msg 39051, Level 16, State 2, Procedure uspPredictSentiment, Line 250
Error occurred during execution of the builtin function 'PREDICT' with HRESULT 0x80070057. Model is corrupt or invalid.*/
go
-- STEP 8 Same proc to train but serialize model for realtimeScoringOnly.
CREATE OR ALTER PROCEDURE [dbo].CreatePyModelRealtimeScoringOnly AS
BEGIN
 DECLARE @model varbinary(max), @train_script nvarchar(max);
 --The Python script we want to execute
 SET @train_script = N'
from microsoftml import rx_logistic_regression,featurize_text, n_gram
from revoscalepy import rx_serialize_model, RxOdbcData, rx_write_object, RxInSqlServer, rx_set_compute_context, RxLocalSeq
#import pickle

connection_string = "Driver=SQL Server;Server=localhost;Database=tpcxbb_1gb;Trusted_Connection=true;"
dest = RxOdbcData(connection_string, table = "models")
 
training_data["tag"] = training_data["tag"].astype("category")

#ngramLength=2: include not only "Word1", "Word2", but also "Word1 Word2"
#weighting="TfIdf": Term frequency & inverse document frequency

modelpy = rx_logistic_regression(formula = "tag ~ features",
								 data = training_data, 
								 method = "multiClass", 
								 ml_transforms=[featurize_text(language="English",
															   cols=dict(features="pr_review_content"),
															   word_feature_extractor=n_gram(2, weighting="TfIdf"))],
								 train_threads=1)

## Serialize and write the model
modelbin = rx_serialize_model(modelpy, realtime_scoring_only = True)
#modelbin = pickle.dumps(model)
rx_write_object(dest, key_name="model_name", key="RevoMMLRealtimeScoring", value_name="model", value=modelbin, serialize=False, compress=None, overwrite=False)'; --overwrite=false on 2019, true on 2017.

 EXECUTE sp_execute_external_script
      @language = N'Python'
       , @script = @train_script
       , @input_data_1 = N'SELECT * FROM product_reviews_training_data'
       , @input_data_1_name = N'training_data'
END;
GO
-- due to not null and pk from previous def.
ALTER TABLE [dbo].[models] ADD DEFAULT 'Py' FOR [language]; 
go
-- STEP 9 Execute the stored procedure that creates and saves the machine learning model in a table
exec  CreatePyModelRealtimeScoringOnly; --00:01:14.560 desktop, 00:02:40.351 laptop.
--Take a look at the model object saved in the model table
SELECT *, datalength(model) as Datalen FROM dbo.models; --(6MB w/rx_write_object vs 55MB w/pickle.dump)
GO
-- incase of OutOfMemoryException: https://docs.microsoft.com/sql/advanced-analytics/r/how-to-create-a-resource-pool-for-r?view=sql-server-2017
-- 1. Limit SQL Server memory usage to 60% of the value in the 'max server memory' setting.
-- 2. Increase Limit memory by external processes to 40% of total computer resources. It defaults to 20%.
-- 3. Reconfigure and restart RG to force changes or restart sql svc.
--ALTER RESOURCE POOL "default" WITH (max_memory_percent = 60); --hmmm...maybe not.
--ALTER EXTERNAL RESOURCE POOL "default" WITH (max_memory_percent = 40); --okay
--ALTER RESOURCE GOVERNOR RECONFIGURE;
go
-- STEP 10 Execute the multi class prediction using the realtime_scoring_only model we trained now.
exec uspPredictSentiment @model='RevoMMLRealtimeScoring'
go
/*Msg 39051, Level 16, State 2, Procedure uspPredictSentiment, Line 304
Error occurred during execution of the builtin function 'PREDICT' with HRESULT 0x80070057. Model is corrupt or invalid.

This is currently not supported.
'rx_logistic_regression' is an algorithm from the mml package, not revoscalepy package.
Cannot demo TSQL PREDICT with a model from 'rx_logistic_regression'.
For now batch predictions by calling rx_predict. 
Use another example instead for native scoring. This sample is good for showing PREDICT:
https://github.com/Microsoft/r-server-hospital-length-of-stay
*/
-- Try sp_rxPredict, if missing, enable it: https://docs.microsoft.com/sql/advanced-analytics/r/how-to-do-realtime-scoring?view=sql-server-2017#bkmk_enableRtScoring
sp_configure 'show advanced options', 1;  
reconfigure;
go
sp_configure 'clr enabled', 1;  
reconfigure with override;
go  
alter database tpcxbb_1gb set trustworthy on; 
exec sp_changedbowner @loginame = sa, @map = false;
go
-- Run cmd as admin: EnableRealtimePredictions.cmd
declare @model_bin varbinary(max)=null
select	@model_bin = model from models where model_name = 'RevoMMLRealtimeScoring';
if @model_bin is not null begin
exec sp_rxPredict @model = @model_bin, @inputData = N'SELECT pr_review_content, cast(tag as varchar(1)) as tag FROM product_reviews_test_data' end;
go --8,999 rows: sp_rxPredict 3-9sec vs python microsoftml rx_predict 11-25sec.
/*
Known issue: sp_rxPredict returns an inaccurate message when a NULL value is passed as the model.

Msg 6522, Level 16, State 1, Procedure sp_rxPredict, Line 334
A .NET Framework error occurred during execution of user-defined routine or aggregate "sp_rxPredict": 
System.InvalidOperationException: Expect a column 'tag' of type: 'String'. Actual type is: 'System.Int32'
System.InvalidOperationException: 
   at Microsoft.MachineLearning.RServerScoring.DataViewAdapter.CheckSame(IEnumerator`1 cols1, IEnumerator`1 cols2)
   at Microsoft.MachineLearning.RServerScoring.DataViewAdapter.Retarget(IDataTable newSource)
   at Microsoft.MachineLearning.RServerScoring.Model.Score(IDataTable inputData)
   at Microsoft.MachineLearning.RServerScoring.Scorer.Score(IModel model, IDataTable inputData, IDictionary`2 scoringParameters, IScoreContext scoreContext)
   at Microsoft.RServer.ScoringLibrary.ScoringHost.ScoreDispatcher.Score(ModelId modelId, IDataTable inputData, IDictionary`2 scoringParameters, IScoreContext scoreContext)
.*/