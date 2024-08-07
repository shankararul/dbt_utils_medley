
{% macro describe(model_name) %}

    {% set variable_types = var('variable_types') %}
    {% set variable_types_text = variable_types['text'] %}
    {% set variable_types_date = variable_types['date'] %}
    {% set variable_types_numeric = variable_types['numeric'] %}
    {% set variable_types_boolean = variable_types['boolean'] %}
    {% set variable_types_time = variable_types['time'] %}

    {% set information_metadata = ((fetch_information_metadata(model_name)) | replace("'", "")| replace("[", " ")| replace("]", " ")  | trim).split(',') %}

    {% set full_path = information_metadata[0] | trim%}
    {% set table_name = information_metadata[1] | trim %}
    {% set db_name = information_metadata[2] | trim | replace(" ", "") %}

    WITH
    meta_data AS (
        -- Need to explicitly cast the type before transposing the data
        SELECT
        column_name
        , data_type
        , COUNT(*) OVER (){{':: STRING' if db_name=='snowflake' else ''}} AS nbr_of_columns
        , {{'COUNT_IF' if db_name=='snowflake' else 'COUNTIF'}}(DATA_TYPE IN {{ variable_types_text }}) OVER () {{':: STRING' if db_name=='snowflake' else ''}}  AS nbr_of_text_columns
        , {{'COUNT_IF' if db_name=='snowflake' else 'COUNTIF'}}(DATA_TYPE IN {{ variable_types_date }}) OVER () {{':: STRING' if db_name=='snowflake' else ''}}  AS nbr_of_date_columns
        , {{'COUNT_IF' if db_name=='snowflake' else 'COUNTIF'}}(DATA_TYPE IN {{ variable_types_numeric }}) OVER () {{':: STRING' if db_name=='snowflake' else ''}}  AS nbr_of_numeric_columns
        , {{'COUNT_IF' if db_name=='snowflake' else 'COUNTIF'}}(DATA_TYPE IN {{ variable_types_boolean }}) OVER () {{':: STRING' if db_name=='snowflake' else ''}}  AS nbr_of_boolean_columns
        , {{'COUNT_IF' if db_name=='snowflake' else 'COUNTIF'}}(DATA_TYPE = '{{ variable_types_time }}') OVER () {{':: STRING' if db_name=='snowflake' else ''}}  AS nbr_of_time_columns
        FROM {{full_path}}.TABLES t
        INNER JOIN {{full_path}}.COLUMNS c ON
                c.table_schema = t.table_schema AND c.table_name = t.table_name
                WHERE t.table_name = '{{table_name}}'
    )
    , meta_data_unique AS (
        SELECT
                DISTINCT
                'dataset' AS identifier
                , NULL AS detail
                , nbr_of_columns
                , nbr_of_text_columns
                , nbr_of_date_columns
                , nbr_of_numeric_columns
                , nbr_of_boolean_columns
                , nbr_of_time_columns
            FROM meta_data
    )
    , unpivot_result AS (
        SELECT
                CASE LOWER(meta_data_key)
                        WHEN 'nbr_of_columns' THEN 1
                        WHEN 'nbr_of_text_columns' THEN 2
                        WHEN 'nbr_of_date_columns' THEN 3
                        WHEN 'nbr_of_numeric_columns' THEN 4
                        WHEN 'nbr_of_boolean_columns' THEN 5
                        WHEN 'nbr_of_time_columns' THEN 6
                END AS index_pos
                , identifier
                , detail
                , meta_data_key
                , meta_data_value
            FROM meta_data_unique
            UNPIVOT (meta_data_value FOR meta_data_key IN (nbr_of_columns, nbr_of_text_columns, nbr_of_date_columns, nbr_of_numeric_columns,nbr_of_boolean_columns,nbr_of_time_columns))
    )
    , row_count AS (
        SELECT
                {{'UPPER' if db_name=='snowflake' else ''}}('nbr_of_rows') AS meta_data_key
                , 'dataset' AS identifier
                , NULL AS detail
                , COUNT(*) AS meta_data_value
        FROM {{ ref(model_name) }}
        GROUP BY 1,2,3
    )
    , column_metadata AS (
        SELECT
            20 + ROW_NUMBER() OVER (ORDER BY data_type) AS index_pos
            , column_name AS meta_data_key
            , data_type AS meta_data_value
            , 'column' AS identifier
            , NULL AS detail
        FROM meta_data
    )
    , assembled_result AS (
        SELECT
                index_pos
                , meta_data_key
                , {{'meta_data_value:: STRING' if db_name=='snowflake' else 'CAST(meta_data_value AS STRING)'}} AS meta_data_value
                , identifier
                , detail
        FROM unpivot_result

        UNION ALL

        SELECT
                0 AS index_pos
                , meta_data_key
                , {{'meta_data_value:: STRING' if db_name=='snowflake' else 'CAST(meta_data_value AS STRING)'}} AS meta_data_value
                , identifier
                , detail
        FROM row_count

        UNION ALL

        SELECT
                index_pos
                , meta_data_key
                , {{'meta_data_value:: STRING' if db_name=='snowflake' else 'CAST(meta_data_value AS STRING)'}} AS meta_data_value
                , identifier
                , detail
        FROM column_metadata
    )

    SELECT
        meta_data_key
        , meta_data_value
        , identifier
        , detail
    FROM assembled_result
    ORDER BY index_pos ASC

{% endmacro %}