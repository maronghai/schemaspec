
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `explicit` (
  `col_int` int NOT NULL,
  `col_dec` decimal(10, 2) NOT NULL,
  `col_var` varchar(256) NOT NULL,
  `col_var0` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
