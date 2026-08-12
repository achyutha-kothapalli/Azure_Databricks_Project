USE [master];
GO

IF DB_ID(N'$(DatabaseName)') IS NOT NULL
BEGIN
    EXEC (N'DROP DATABASE [$(DatabaseName)];');
END;
GO
