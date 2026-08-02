
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `user` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL,
  `phone` varchar(16) NOT NULL,
  INDEX `idx_name` (`name`),
  UNIQUE INDEX `uk_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
