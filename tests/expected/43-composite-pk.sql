
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `composite_pk` (
  `user_id` int NOT NULL PRIMARY KEY,
  `role_id` int NOT NULL PRIMARY KEY,
  `granted` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
