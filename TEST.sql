CHECKPOINT;
GO
DBCC DROPCLEANBUFFERS;
GO

EXEC [prHCA2] '2013-11-20 23:59:01.000', 'Test', 'RN, PCT, LPN'
GO
CHECKPOINT;
GO
DBCC DROPCLEANBUFFERS;
GO

EXEC [prHCA1] '2013-11-20 23:59:01.000', 'Test', 'RN, PCT, LPN'
GO
CHECKPOINT;
GO
DBCC DROPCLEANBUFFERS;
GO

EXEC [prHCA] '2013-11-20 23:59:01.000', 'Test', 'RN, PCT, LPN'
GO
