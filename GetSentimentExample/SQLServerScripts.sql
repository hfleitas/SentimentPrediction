-- blog: https://blogs.msdn.microsoft.com/sqlserverstorageengine/2017/11/01/sentiment-analysis-with-python-in-sql-server-machine-learning-services/

--  + --------------------- +
--  | 1. restore sample db. |
--  + --------------------- +
--The database used for this sample can be downloaded here: https://sqlchoice.blob.core.windows.net/sqlchoice/static/tpcxbb_1gb.bak
restore filelistonly from disk = 'c:\users\hfleitas\downloads\tpcxbb_1gb.bak'
go
restore database [tpcxbb_1gb] from disk = 'c:\users\hfleitas\downloads\tpcxbb_1gb.bak' with replace,
move 'tpcxbb_1gb' to 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\tpcxbb_1gb.mdf', 
move 'tpcxbb_1gb_log' to 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\DATA\tpcxbb_1gb.ldf'
go
alter database [tpcxbb_1gb] set COMPATIBILITY_LEVEL = 140
GO
EXEC sp_configure 'external scripts enabled', 1
RECONFIGURE WITH OVERRIDE
go
declare @sql nvarchar(max)
select @sql = 'grant EXECUTE ANY EXTERNAL SCRIPT to ['+ @@servername +'\SQLRUserGroup]'
print @sql; exec sp_executesql @sql
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
go --0.5	Negative. Why...Not enough?
-- https://azure.microsoft.com/en-us/services/cognitive-services/text-analytics/ 
-- Language: English, Sentiment: 78%.
-- Key phrases: face of fear, existence, triumph, valor, sense of purpose, entire lives, quiet desperation, shoulders, greater heights, precursor, Destiny, gift, Master Jim, burden, truth, hero. 



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
                                      word_feature_extractor=n_gram(2, weighting="TfIdf"))])

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
-- Ie. since the�re all tag 3 positive, they will have very low negative scores, low neutral scores and very high positive scores. 
EXECUTE [dbo].[predict_review_sentiment] 
GO
--EXECUTE statement failed because its WITH RESULT SETS clause specified 5 column(s) for result set number 1, but the statement sent 6 column(s) at run time.
--fixed by seeing actual output using print(result) in messages tab.
