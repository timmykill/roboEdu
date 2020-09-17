const puppeteer = require('puppeteer');

(async () => {
	const browser = await puppeteer.launch({args: ['--disable-notifications', '--use-fake-ui-for-media-stream', '--window-size=1920,1080', '--kiosk'], headless: false, defaultViewport: {width: 1920, height:1080}});
//	const browser = await puppeteer.launch({args: ['--use-fake-ui-for-media-stream', '--disable-infobars'], headless: false});
	const page = await browser.newPage();

	await page.goto('https://alicedreamt.bandcamp.com/album/the-wretched-world');

	await page.waitForSelector('div.playbutton');
	await page.click('div.playbutton');


	await page.waitForTimeout(10000000)

	await browser.close();
})();
