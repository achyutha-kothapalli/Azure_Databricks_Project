USE [$(DatabaseName)];
GO

IF SCHEMA_ID(N'gold') IS NULL
BEGIN
    EXEC (N'CREATE SCHEMA [gold] AUTHORIZATION [dbo];');
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_scoped_credentials
    WHERE [name] = N'WorkspaceIdentity'
)
BEGIN
    CREATE DATABASE SCOPED CREDENTIAL [WorkspaceIdentity]
    WITH IDENTITY = 'Managed Identity';
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.external_data_sources
    WHERE [name] = N'SilverDataSource'
)
BEGIN
    CREATE EXTERNAL DATA SOURCE [SilverDataSource]
    WITH (
        LOCATION = 'https://$(StorageAccount).dfs.core.windows.net/silver',
        CREDENTIAL = [WorkspaceIdentity]
    );
END;
GO

IF EXISTS (
    SELECT 1
    FROM sys.external_data_sources
    WHERE [name] = N'SilverDataSource'
      AND [location] <> N'https://$(StorageAccount).dfs.core.windows.net/silver'
)
BEGIN
    THROW 51000, 'SilverDataSource points to an unexpected storage location.', 1;
END;
GO
