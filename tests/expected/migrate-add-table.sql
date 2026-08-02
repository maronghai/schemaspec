-- Migration: schema diff

BEGIN;

CREATE TABLE `post` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `title` varchar(128) NOT NULL,
  `user_id` int NOT NULL,
  INDEX `idx_user_id` (`user_id`),
  FOREIGN KEY (`user_id`) REFERENCES `user`(`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


COMMIT;
