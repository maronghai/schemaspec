import { Entity, PrimaryGeneratedColumn, Column, ManyToOne, JoinColumn } from 'typeorm';

@Entity('FK')
// Test
export class FK {
}

@Entity('users')
export class users {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'varchar', length: 32 })
  name: string;

}

@Entity('orders')
export class orders {
  @PrimaryGeneratedColumn()
  id: number;

  @ManyToOne(() => users)
  @JoinColumn({ name: 'user_id' })
  user_id: users;

  @Column({ type: 'decimal', precision: 16, scale: 2 })
  amount: number;

}
