#!/usr/bin/env -S node
import type { Contract as End } from '../../snapshots/025f8e241f3d24e21506951748d97456a23b0052c47f11b06a011b96045ca4d6/contract';
import endContract from '../../snapshots/025f8e241f3d24e21506951748d97456a23b0052c47f11b06a011b96045ca4d6/contract.json' with { type: 'json' };
import type { Contract as Start } from '../../snapshots/e61cfd8d9efd930d2ffa67e17bf7036148786d0b1f1c38e36b23b76a38d71854/contract';
import startContract from '../../snapshots/e61cfd8d9efd930d2ffa67e17bf7036148786d0b1f1c38e36b23b76a38d71854/contract.json' with { type: 'json' };
import { Migration, MigrationCLI, col } from '@prisma/orm-postgres/migration';

export default class M extends Migration<Start, End> {
  override readonly startContractJson = startContract;
  override readonly endContractJson = endContract;

  override get operations() {
    return [
      this.addColumn({
        schema: 'public',
        table: 'SpotCommentReport',
        column: col('details', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SpotCommunityDescriptionReport',
        column: col('details', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
      this.addColumn({
        schema: 'public',
        table: 'SpotMediaReport',
        column: col('details', 'text', { codecRef: { codecId: 'pg/text@1' } }),
      }),
    ];
  }
}

MigrationCLI.run(import.meta.url, M);
