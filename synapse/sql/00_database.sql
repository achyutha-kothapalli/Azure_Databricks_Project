USE [master];
GO

IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    EXEC (
        N'CREATE DATABASE [$(DatabaseName)] COLLATE Latin1_General_100_BIN2_UTF8;'
    );
END;
GO

USE [$(DatabaseName)];
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.symmetric_keys
    WHERE [name] = N'##MS_DatabaseMasterKey##'
)
BEGIN
    EXEC (
        N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''$(MasterKeyPassword)'';'
    );
END;
GO
