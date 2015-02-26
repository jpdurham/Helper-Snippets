/* 
 * DESCRIPTION: Adds a sproc to your database that allows you to search for a guid in
 * every table on the database and optionally executes a select on the first
 * returned result (by default).
 *
 * PARAMETERS: @query_text nvarchar(255)
 *	           @execute_select bit = 1
 * SIDE-EFFECT: This will delete any sproc name [dbo].[SearchForGuidInAllTables]
 *              and replace it with the new implementation below.
 *
 * NOTE: There are no other side-effects besides the one mentioned above.
*/

IF EXISTS (
   SELECT *
   FROM sys.procedures
   WHERE [object_id] = OBJECT_ID(N'[dbo].[SearchForGuidInAllTables]'))
BEGIN
   DROP PROCEDURE [dbo].[SearchForGuidInAllTables];
END;
GO

CREATE PROCEDURE [dbo].[SearchForGuidInAllTables] 
	@query_text nvarchar(255)
	,@execute_select bit = 1
AS

SET NOCOUNT ON;

BEGIN
    CREATE TABLE #tables (
        schema_name nvarchar(50), table_name nvarchar(255),
        column_name nvarchar(255), type_name nvarchar(50)
    )

    INSERT INTO #tables SELECT * FROM (
        SELECT schema_name, table_name, column_name, type_name
        FROM (
            SELECT name table_name, object_id table_id, schema_id
            FROM sys.tables
        ) [table]
        LEFT JOIN (
            SELECT schema_id, sys.schemas.name schema_name
            FROM sys.schemas
        ) [schema] ON [table].schema_id = [schema].schema_id
        LEFT JOIN (
            SELECT object_id table_id, name column_name, system_type_id type_id
            FROM sys.columns columns
        ) [column] ON [column].table_id = [table].table_id
        LEFT JOIN (
            SELECT name type_name, system_type_id type_id 
            FROM sys.types
        ) type ON [column].type_id = type.type_id
    ) tablecolumn
    WHERE type_name = 'uniqueidentifier'
    ORDER BY table_name

    DECLARE @sql            nvarchar(max);
    DECLARE @schema_name    nvarchar(50);
    DECLARE @table_name     nvarchar(50);
    DECLARE @column_name    nvarchar(50);

    CREATE TABLE #results (
         query nvarchar(max), schema_name nvarchar(50),
         table_name nvarchar(255), column_name nvarchar(255), row_count int
     )

    DECLARE table_cursor CURSOR FOR 
    SELECT schema_name, table_name, column_name FROM #tables
    OPEN table_cursor FETCH NEXT FROM table_cursor INTO @schema_name, @table_name, @column_name   

    WHILE @@fetch_STATUS = 0  
    BEGIN
        SET @sql = 'INSERT INTO #results SELECT ''SELECT [' + @column_name + '], *  FROM [' 
                 + @schema_name + '].[' +  @table_name + '] WHERE [' + @column_name + '] = ''''' 
                 + @query_text + ''''''' query, ''' + @schema_name + ''' [schema_name], ''' 
                 + @table_name + ''' [table_name], ''' + @column_name 
                 + ''' [column_name], COUNT(-1) row_count FROM [' + @schema_name + '].[' 
                 +  @table_name + '] WHERE [' + @column_name + '] =  ''' + @query_text + '''; '; 
        EXECUTE sp_ExecuteSQL @sql;
        FETCH NEXT FROM table_cursor INTO @schema_name, @table_name, @column_name   
    END
    
    CLOSE table_cursor  
    DEALLOCATE table_cursor 
    
    SELECT * FROM #results WHERE 0 < row_count ORDER BY row_count DESC;
	
    DECLARE @statement nvarchar(max) = (
    	SELECT TOP 1 query 
    	FROM #results 
    	WHERE 0 < row_count 
    	ORDER BY row_count DESC
    );
    
    IF @execute_select = 1
    BEGIN
    	EXEC sp_executesql @statement;
    END

    DROP TABLE #tables
    DROP TABLE #results
END
GO
