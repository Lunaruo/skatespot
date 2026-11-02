#!/usr/bin/env -S node
import type { Contract as Start } from '../../snapshots/4bced383a72f1180b90ba064e0b0f2f84d58acbb54077f4b9888b5fcdf3a1a71/contract';
import startContract from '../../snapshots/4bced383a72f1180b90ba064e0b0f2f84d58acbb54077f4b9888b5fcdf3a1a71/contract.json' with { type: 'json' };
import type { Contract as End } from '../../snapshots/e61cfd8d9efd930d2ffa67e17bf7036148786d0b1f1c38e36b23b76a38d71854/contract';
import endContract from '../../snapshots/e61cfd8d9efd930d2ffa67e17bf7036148786d0b1f1c38e36b23b76a38d71854/contract.json' with { type: 'json' };
import { Migration, MigrationCLI, col, fn, lit, primaryKey } from '@prisma/orm-postgres/migration';

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      this.createTable({
        schema: 'public',
        table: 'SpotCommentReport',
        columns: [
          col('commentId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('contentSnapshot', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('reason', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('reporterId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('reviewedAt', 'timestamptz', { codecRef: { codecId: 'pg/timestamptz-string@1' } }),
          col('status', 'text', {
            notNull: true,
            default: lit('pending'),
            codecRef: { codecId: 'pg/text@1' },
          }),
        ],
        constraints: [primaryKey(['id'])],
      }),
      this.createTable({
        schema: 'public',
        table: 'SpotCommunityDescriptionReport',
        columns: [
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('descriptionSnapshot', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('reason', 'text', { notNull: true, codecRef: { codecId: 'pg/text@1' } }),
          col('reporterId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('reviewedAt', 'timestamptz', { codecRef: { codecId: 'pg/timestamptz-string@1' } }),
          col('spotId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('status', 'text', {
            notNull: true,
            default: lit('pending'),
            codecRef: { codecId: 'pg/text@1' },
          }),
        ],
        constraints: [primaryKey(['id'])],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotCommentReport',
        index: 'SpotCommentReport_commentId_idx_b5a4f615',
        columns: ['commentId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotCommentReport',
        index: 'SpotCommentReport_reporterId_idx_aa245831',
        columns: ['reporterId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotCommentReport',
        index: 'SpotCommentReport_status_idx_e98638ab',
        columns: ['status'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotCommunityDescriptionReport',
        index: 'SpotCommunityDescriptionReport_reporterId_idx_aa245831',
        columns: ['reporterId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotCommunityDescriptionReport',
        index: 'SpotCommunityDescriptionReport_spotId_idx_2a0d61dc',
        columns: ['spotId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotCommunityDescriptionReport',
        index: 'SpotCommunityDescriptionReport_status_idx_e98638ab',
        columns: ['status'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotMediaReport',
        index: 'SpotMediaReport_status_idx_e98638ab',
        columns: ['status'],
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'SpotCommentReport',
        foreignKey: {
          name: 'SpotCommentReport_commentId_fkey',
          columns: ['commentId'],
          references: { schema: 'public', table: 'SpotComment', columns: ['id'] },
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'SpotCommentReport',
        foreignKey: {
          name: 'SpotCommentReport_reporterId_fkey',
          columns: ['reporterId'],
          references: { schema: 'public', table: 'User', columns: ['id'] },
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'SpotCommunityDescriptionReport',
        foreignKey: {
          name: 'SpotCommunityDescriptionReport_spotId_fkey',
          columns: ['spotId'],
          references: { schema: 'public', table: 'SkateSpot', columns: ['id'] },
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'SpotCommunityDescriptionReport',
        foreignKey: {
          name: 'SpotCommunityDescriptionReport_reporterId_fkey',
          columns: ['reporterId'],
          references: { schema: 'public', table: 'User', columns: ['id'] },
        },
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
