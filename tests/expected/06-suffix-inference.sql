
CREATE DATABASE `demo` CHARACTER SET utf8mb4;

CREATE TABLE `suffixes` (
  `user_id` int NOT NULL,
  `order_id` int NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `paid_on` date NOT NULL,
  `deleted_on` date NOT NULL,
  `name` varchar(255) NOT NULL,
  `content` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
