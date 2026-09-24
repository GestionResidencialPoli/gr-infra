-- Postgres solo crea automaticamente la base indicada en POSTGRES_DB
-- (gr_user_db). El resto de servicios que comparten esta misma instancia
-- necesitan su propia base logica; se agrega una linea aqui por cada
-- servicio nuevo que necesite base de datos propia.
CREATE DATABASE gr_wall_db;
