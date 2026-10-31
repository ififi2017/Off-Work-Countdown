/** Source verification is separate from the pending human review of page copy. */
export const cnPayReference = {
  basisId: "cn-monthly-pay-21.75-2025",
  title: "人力资源社会保障部关于职工全年月平均工作时间和工资折算问题的通知",
  sourceUrls: ["https://app.www.gov.cn/govdata/gov/202501/02/523227/article.html"],
  noticeDate: "2025-01-01",
  sourcePublishedAt: "2025-01-02",
  // The notice is dated January 1; it does not state a separate effective date.
  effectiveFrom: null,
  reviewedAt: "2026-10-31",
  appliesTo: "中国大陆该通知所述职工日工资、小时工资的折算参考",
  exclusions: "不据此判断请假扣薪、加班费、税后到手收入或某个具体劳动合同的合规性；不作为实际出勤日历。",
  payDaysPerMonth: 21.75,
  hoursPerDay: 8,
  systemWorkdaysPerMonth: 20.67,
} as const;
