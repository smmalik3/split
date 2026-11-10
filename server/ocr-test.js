const { createWorker } = require('tesseract.js');
(async () => {
  console.log('creating worker...');
  const worker = await createWorker('eng', 1, {
    cachePath: '/home/hatch/workspace/splitwise-app/data/tesseract-cache',
    langPath: '/home/hatch/workspace/splitwise-app/data/tesseract-cache',
    logger: m => console.log('LOG', m.status, m.progress),
  });
  console.log('worker ready, recognizing...');
  const { data } = await worker.recognize('/home/hatch/workspace/splitwise-app/data/test/receipt.png');
  console.log('TEXT:\n' + data.text);
  console.log('confidence:', data.confidence);
  await worker.terminate();
  process.exit(0);
})().catch(e => { console.error('ERR', e); process.exit(1); });
