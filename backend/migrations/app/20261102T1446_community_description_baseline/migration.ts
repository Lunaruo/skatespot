#!/usr/bin/env -S node
import type { Contract as End } from '../../snapshots/4bced383a72f1180b90ba064e0b0f2f84d58acbb54077f4b9888b5fcdf3a1a71/contract';
import endContract from '../../snapshots/4bced383a72f1180b90ba064e0b0f2f84d58acbb54077f4b9888b5fcdf3a1a71/contract.json' with { type: 'json' };
import type { Contract as Start } from '../../snapshots/85fa2bf6a97f879e1fa81043b057e5ebe6e2633a31e0c5922e93fbcd00bacb67/contract';
import startContract from '../../snapshots/85fa2bf6a97f879e1fa81043b057e5ebe6e2633a31e0c5922e93fbcd00bacb67/contract.json' with { type: 'json' };
import { Migration, MigrationCLI, col, fn, lit, primaryKey } from '@prisma/orm-postgres/migration';

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      this.createTable({
        schema: 'public',
        table: 'SpotMediaReport',
        columns: [
          col('createdAt', 'timestamptz', {
            notNull: true,
            default: fn('now()'),
            codecRef: { codecId: 'pg/timestamptz-string@1' },
          }),
          col('id', 'SERIAL', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
          col('mediaId', 'int4', { notNull: true, codecRef: { codecId: 'pg/int4@1' } }),
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
      this.addColumn({
        schema: 'public',
        table: 'SkateSpot',
        column: col('communityDescription', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SkateSpot',
        column: col('communityDescriptionAuthorId', 'int4', { codecRef: { codecId: 'pg/int4@1' } }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SkateSpot',
        column: col('communityDescriptionUpdatedAt', 'timestamptz', {
          codecRef: { codecId: 'pg/timestamptz-string@1' },
        }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SkateSpot',
        column: col('externalId', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SkateSpot',
        column: col('externalSource', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SpotMedia',
        column: col('deletedAt', 'timestamptz', {
          codecRef: { codecId: 'pg/timestamptz-string@1' },
        }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SpotMedia',
        column: col('moderationReason', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SpotMedia',
        column: col('moderationStatus', 'text', {
          notNull: true,
          default: lit('approved'),
          codecRef: { codecId: 'pg/text@1' },
        }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SpotMedia',
        column: col('storageKey', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addUnique({
        schema: 'public',
        table: 'SkateSpot',
        constraint: 'SkateSpot_externalSource_externalId_key',
        columns: ['externalSource', 'externalId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SkateSpot',
        index: 'SkateSpot_communityDescriptionAuthorId_idx_6f61b6f8',
        columns: ['communityDescriptionAuthorId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotMediaReport',
        index: 'SpotMediaReport_mediaId_idx_6b06655c',
        columns: ['mediaId'],
      }),
      this.createIndex({
        schema: 'public',
        table: 'SpotMediaReport',
        index: 'SpotMediaReport_reporterId_idx_aa245831',
        columns: ['reporterId'],
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'SkateSpot',
        foreignKey: {
          name: 'SkateSpot_communityDescriptionAuthorId_fkey',
          columns: ['communityDescriptionAuthorId'],
          references: { schema: 'public', table: 'User', columns: ['id'] },
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'SpotMediaReport',
        foreignKey: {
          name: 'SpotMediaReport_mediaId_fkey',
          columns: ['mediaId'],
          references: { schema: 'public', table: 'SpotMedia', columns: ['id'] },
        },
      }),
      this.addForeignKey({
        schema: 'public',
        table: 'SpotMediaReport',
        foreignKey: {
          name: 'SpotMediaReport_reporterId_fkey',
          columns: ['reporterId'],
          references: { schema: 'public', table: 'User', columns: ['id'] },
        },
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
