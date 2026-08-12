USE [$(DatabaseName)];
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE [name] = N'$(ReaderPrincipal)'
)
BEGIN
    EXEC (N'CREATE USER [$(ReaderPrincipal)] FROM EXTERNAL PROVIDER;');
END;
GO

GRANT SELECT ON SCHEMA::[gold] TO [$(ReaderPrincipal)];
GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::[WorkspaceIdentity]
    TO [$(ReaderPrincipal)];
DENY ADMINISTER DATABASE BULK OPERATIONS TO [$(ReaderPrincipal)];
GO
