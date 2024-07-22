import { test, expect } from '@playwright/test';
import { addAndRemoveTasks } from './test-helpers';

const taskCount = parseFloat(process.env.TASK_COUNT || 500);

test('reactive', async ({ page }) => {
  await addAndRemoveTasks({ page, reactive: true, taskCount });
});
