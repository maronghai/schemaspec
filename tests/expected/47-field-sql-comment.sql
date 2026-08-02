
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `sql_comment_field` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
