
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL,
  `active` boolean NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
