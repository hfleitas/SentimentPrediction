create or alter proc GetTrollhunterModel (
	@Name nvarchar(30) = 'TrollhunterRealtime',
	@Languange varchar(30) = 'Python',
	@Svr varchar(128) = 'localhost',
	@Db	nvarchar(128) = 'FleitasArts'
)
as	
	declare @model varbinary(max), @train_script nvarchar(max);
	delete top(1) from models where name = @Name and language = @Languange;
	
	--The Python script we want to execute
	set @train_script = N'
from microsoftml import rx_logistic_regression, featurize_text, n_gram
from revoscalepy import rx_serialize_model, RxOdbcData, rx_write_object, RxInSqlServer, rx_set_compute_context, RxLocalSeq

connection_string = "Driver=SQL Server;Server='+@Svr+';Database='+@Db+';Trusted_Connection=true;"
dest = RxOdbcData(connection_string, table = "models")
 
training_data["tag"] = training_data["tag"].astype("category")

modelpy = rx_logistic_regression(formula = "tag ~ features",
								 data = training_data, 
								 method = "multiClass", 
								 ml_transforms=[featurize_text(language="English",
															   cols=dict(features="quote"),
															   word_feature_extractor=n_gram(2, weighting="TfIdf"))],
								 train_threads=1)

modelbin = rx_serialize_model(modelpy, realtime_scoring_only = True)
rx_write_object(dest, key_name="Name", key="'+@Name+'", value_name="Model", value=modelbin, serialize=False, compress=None, overwrite=False)'; --overwrite=false on 2019, true on 2017.

	exec sp_execute_external_script @language = N'Python'
		,@script = @train_script
		,@input_data_1 = N'select * from QuotesForTraining'
		,@input_data_1_name = N'training_data'
go

exec  GetTrollhunterModel; --00:00:02.919 home desktop.

select *, datalength(model) as Datalen from dbo.models; 