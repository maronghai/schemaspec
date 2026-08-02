
CREATE DATABASE `test_custom_types` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `uuid` varchar(36) NOT NULL,
  `email` varchar(128) NOT NULL,
  `name` varchar(64) NOT NULL,
  `ip` varchar(45) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
