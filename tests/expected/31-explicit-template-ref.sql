
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `version` bigint NOT NULL,
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `product` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `version` bigint NOT NULL,
  `name` varchar(128) NOT NULL,
  `price` decimal(16, 2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
