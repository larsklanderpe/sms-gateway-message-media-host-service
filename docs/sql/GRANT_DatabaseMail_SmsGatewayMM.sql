-- ============================================================
-- Grant Database Mail rights to the SMS Gateway service login
-- ============================================================
-- WHY:
--   PE_CHECK_BONUS_AWARD_QUEUE_MM reads msdb.dbo.sysmail_sentitems (queue-depth
--   alert rate-limit) and calls msdb.dbo.sp_send_dbmail (orphan + queue alerts).
--   Without Database Mail rights the service login hits:
--     "The SELECT permission was denied on the object 'sysmail_sentitems',
--      database 'msdb', schema 'dbo'."
--   and the BonusAward feed cannot poll.
--
--   DatabaseMailUserRole is SQL Server's designed least-privilege role for this:
--   it grants EXEC sp_send_dbmail and lets the login read its OWN rows in the
--   sysmail_* views (the views filter by security context, which is all the
--   rate-limit check needs).
--
-- RUN AS: a sysadmin, once per barrel DB server.
-- ============================================================

-- >>> Set this to the login the service connects as (from BarrelConnectionString
-- >>> in C:\peservices\configs\appsettings-SMSGMM.json).
--   - SQL auth:      the "User ID=" value, e.g. 'svc_smsgateway'
--   - Windows auth:  the service account, e.g. 'DOMAIN\svc-smsgmm' or
--                    'NT SERVICE\SMS Gateway MessageMedia'
DECLARE @login SYSNAME = N'<SERVICE_LOGIN>';

USE msdb;

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @login)
BEGIN
    DECLARE @createUser NVARCHAR(MAX) =
        N'CREATE USER ' + QUOTENAME(@login) + N' FOR LOGIN ' + QUOTENAME(@login) + N';';
    EXEC sp_executesql @createUser;
END

ALTER ROLE DatabaseMailUserRole ADD MEMBER @login;
GO

-- ============================================================
-- VERIFY
-- ============================================================
USE msdb;

-- Should list the service login as a member of DatabaseMailUserRole:
SELECT r.name AS role_name, m.name AS member_name
FROM sys.database_role_members drm
JOIN sys.database_principals r ON r.principal_id = drm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = drm.member_principal_id
WHERE r.name = 'DatabaseMailUserRole'
ORDER BY m.name;
