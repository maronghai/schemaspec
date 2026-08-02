
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `multi` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `name` varchar(32) NOT NULL,
  `email` varchar(128) NOT NULL,
  `status` int NOT NULL,
  INDEX `idx_name_email` (`name`, `email`),
  UNIQUE INDEX `uk_email_status` (`email`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
