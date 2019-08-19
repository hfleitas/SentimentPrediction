create or alter proc GetCognitiveAPIQuoteSentiment
as
	set nocount on;
	declare @py nvarchar(max);
	
	set @py = N'import requests, pprint as pr
from pandas.io.json import json_normalize

subscription_key = "3f2a24704b464e03a804cc0d0d916172" 
text_analytics_base_url = "https://eastus2.api.cognitive.microsoft.com/text/analytics/v2.0/"
sentiment_url = text_analytics_base_url + "sentiment"

df = jsondocs

headers  = {"Ocp-Apim-Subscription-Key": subscription_key, "content-type": "application/json"}
response = requests.post(sentiment_url, headers = headers, data = df.iloc[0][0].encode()) 

rds = response.json()
df2 = json_normalize(rds, "documents")

pr.pprint(rds)
print(type(df2),df2,sep="\n")
'; 

	drop table if exists apiresults;
	create table apiresults (id int, score float);

	insert into apiresults
	exec sp_execute_external_script @language = N'Python'
		,@script = @py
		,@input_data_1 = N'select * from JsonQuotes'
		,@input_data_1_name = N'jsondocs'
   		,@output_data_1_name =  N'df2'
	select * from apiresults;	
	
	update 	q 
		set q.Sentiment = a.Score
	from 	Quotes q
	inner join apiresults a
		on q.quoteid = a.id
	where 	q.Sentiment is null;
go

exec GetCognitiveAPIQuoteSentiment;

select * from Quotes;