// 报告流水线看门狗 · 条件评估脚本（every 15m）
// 规则：仅 07:00–15:00 活跃；扫描未完成且未在运行→补跑（日限2次）；
//       扫描完成但晨报未发→补发（日限1次）；其余情况静默。
// 状态持久化于 trigger.state：{date, rescans, briefs}
const now = new Date();
const pad = n => String(n).padStart(2, '0');
const d = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
const hour = now.getHours();
const st = trigger.state || {};
const rescans = st.date === d ? (st.rescans || 0) : 0;
const briefs = st.date === d ? (st.briefs || 0) : 0;
const OC = '/home/desmond/.nvm/versions/node/v26.8.1/bin/openclaw';
let result = { fire: false, state: { date: d, rescans: rescans, briefs: briefs } };

if (hour >= 7 && hour < 15) {
  const res = await exec({ command: 'bash /home/desmond/plans/2026-09-02-2139-openclaw-doctor-fixes/看门狗探针.sh' });
  const out = String((res && (res.aggregated || res.text)) || '');
  const grab = tag => { const m = out.match(new RegExp('\\b' + tag + '=(\\S+)')); return m ? m[1] : '?'; };
  const S = grab('S'), M = grab('M'), R1 = grab('R1'), R2 = grab('R2');
  const scanRunning = R1 !== 'no' && R1 !== '?' && R1 !== 'null';
  const briefRunning = R2 !== 'no' && R2 !== '?' && R2 !== 'null';

  if (!(S === 'Y' && M === 'Y')) {
    if (S !== 'Y') {
      if (!scanRunning && R1 !== '?' && rescans < 2) {
        result = {
          fire: true,
          message: '看门狗触发：今日(' + d + ')扫描未完成且未在运行（自动补跑第 ' + (rescans + 1) + '/2 次）。请用 exec 执行：' + OC + ' automations run 72bbfb86-6a82-4563-a4e1-911abc3e75c8 然后用中文一句话确认（执行了自动补跑、是否成功入队），不要做其他事。',
          state: { date: d, rescans: rescans + 1, briefs: briefs }
        };
      }
    } else if (!briefRunning && R2 !== '?' && briefs < 1) {
      result = {
        fire: true,
        message: '看门狗触发：今日(' + d + ')扫描已完成但晨报未送达。请用 exec 执行：' + OC + ' automations run c93a7761-7fd8-40b5-ac86-f451712424af 然后用中文一句话确认（已触发晨报补发、是否成功入队），不要做其他事。',
        state: { date: d, rescans: rescans, briefs: briefs + 1 }
      };
    }
  }
}
json(result);
