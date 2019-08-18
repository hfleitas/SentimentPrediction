sp_configure 'show advanced options', 1;  
reconfigure;
go
sp_configure 'clr enabled', 1;  
reconfigure with override;
go  
alter database current set trustworthy on; 
exec sp_changedbowner @loginame = sa, @map = false;
go