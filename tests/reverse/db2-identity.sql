-- Db2 identity columns and data types
CREATE TABLE employees (
  id INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255),
  salary DECIMAL(10,2) DEFAULT 0,
  active BOOLEAN DEFAULT TRUE,
  bio CLOB,
  PRIMARY KEY (id)
);
