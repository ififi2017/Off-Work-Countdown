import vm from "node:vm";
import { createRulesScript } from "./build-ios-native-rules.mjs";

// The TypeScript side of plan 019 R1 and R2. iOS resolves shifts, snapshots,
// Widget shifts, Watch projections, range expansion and reminders in
// ScheduleRules.swift; these entry points keep the exact TypeScript behaviour
// those used to run through JavaScriptCore, so the generated fixtures can hold
// the Swift port to it. Nothing here ships in the app.
const ORACLE_BODY = `
  const reminders = require("./reminders");
  const summary = require("./summary");
  const watchProjection = require("./watch-projection");

  function shiftOptions(input) {
    return {
      breakStartTime: input.breakStartTime || null,
      breakDurationMinutes: input.breakDurationMinutes || 0,
      overtimeEndAtMs: input.overtimeEndAtMs || null,
    };
  }

  function inputTimeZone(input) {
    return typeof input.timeZoneIdentifier === "string" && input.timeZoneIdentifier.trim()
      ? input.timeZoneIdentifier.trim()
      : null;
  }

  function resolveCurrentShift(input) {
    const options = shiftOptions(input);
    const timeZone = inputTimeZone(input);
    const live = countdown.buildShiftTimeline(
      input.startTime,
      input.endTime,
      new Date(input.nowMs),
      options,
      timeZone
    );
    const ended = countdown.findEndedShiftOnEndCalendarDay({
      startTime: input.startTime,
      endTime: input.endTime,
      nowMs: input.nowMs,
      workdays: input.workdays,
      schedule: input.schedule || null,
      options,
      forcedWorkdayStartMs: input.forcedWorkdayStartMs || null,
      timeZone,
    });
    const liveStart = countdown.getShiftStartAtMs(live);
    const liveEnd = countdown.getShiftEndAtMs(live);
    // Settlement of last night's overnight only applies until tonight's
    // window actually starts. A rest-day 22:00–06:00 on Saturday would
    // otherwise stay pinned to Friday's 06:00 end all evening, including a
    // forced Saturday night run.
    const liveIsOpen = input.nowMs >= liveStart && input.nowMs < liveEnd;
    if (
      ended &&
      countdown.getShiftStartAtMs(ended) !== liveStart &&
      !liveIsOpen
    ) {
      return ended;
    }
    return live;
  }

  function startOfLocalDayMs(date, timeZone) {
    return countdown.startOfCivilDayMs(
      date instanceof Date ? date.getTime() : Number(date),
      timeZone || null
    );
  }

  function isScheduledShift(input, shift) {
    return countdown.isScheduledWorkday(
      new Date(countdown.getShiftStartAtMs(shift)),
      input.workdays,
      input.schedule || null,
      inputTimeZone(input)
    );
  }

  function isForcedShift(input, shift) {
    if (!(typeof input.forcedWorkdayStartMs === "number")) return false;
    const timeZone = inputTimeZone(input);
    return startOfLocalDayMs(countdown.getShiftStartAtMs(shift), timeZone) ===
      startOfLocalDayMs(input.forcedWorkdayStartMs, timeZone);
  }

  function isActualShift(input, shift) {
    return isScheduledShift(input, shift) || isForcedShift(input, shift);
  }

  // The rest-day ring starts after the previous shift's settlement day and
  // advances monotonically across the rest interval. On the target workday it
  // becomes the ordinary midnight-to-clock-in ring, so 00:08 before 09:00
  // reads about 1.5%, not 98.5%.
  function countdownAnchorAtMs(input, targetAtMs) {
    const timeZone = inputTimeZone(input);
    if (!timeZone) {
      const targetDay = new Date(targetAtMs);
      targetDay.setHours(0, 0, 0, 0);

      for (let offset = 1; offset <= 366; offset += 1) {
        const candidateDay = new Date(targetDay);
        candidateDay.setDate(candidateDay.getDate() - offset);
        const candidateStart = countdown.atTime(candidateDay, input.startTime);
        if (!countdown.isScheduledWorkday(
          candidateStart,
          input.workdays,
          input.schedule || null
        )) {
          continue;
        }

        const previous = countdown.buildShiftTimeline(
          input.startTime,
          input.endTime,
          candidateDay,
          {
            breakStartTime: input.breakStartTime || null,
            breakDurationMinutes: input.breakDurationMinutes || 0,
          }
        );
        const anchor = new Date(countdown.getShiftEndAtMs(previous));
        anchor.setHours(0, 0, 0, 0);
        anchor.setDate(anchor.getDate() + 1);
        if (anchor.getTime() < targetAtMs) return anchor.getTime();
      }
      return targetDay.getTime();
    }

    const targetDayMs = startOfLocalDayMs(targetAtMs, timeZone);
    for (let offset = 1; offset <= 366; offset += 1) {
      const candidateDayMs = countdown.addCivilDaysMs(targetDayMs, -offset, timeZone);
      // Probe from the middle of the candidate day, the way
      // expandScheduleRangeInZone and findEndedShiftOnEndCalendarDayInZone do.
      // From civil midnight an overnight 22:00-06:00 resolves to the *previous*
      // day's shift, so both the workday test and the anchor slid a day back.
      const candidateProbeMs = candidateDayMs + 12 * 3_600_000;
      const previous = countdown.buildShiftTimeline(
        input.startTime,
        input.endTime,
        new Date(candidateProbeMs),
        {
          breakStartTime: input.breakStartTime || null,
          breakDurationMinutes: input.breakDurationMinutes || 0,
        },
        timeZone
      );
      if (!countdown.isScheduledWorkday(
        new Date(countdown.getShiftStartAtMs(previous)),
        input.workdays,
        input.schedule || null,
        timeZone
      )) {
        continue;
      }
      const anchorMs = countdown.addCivilDaysMs(
        startOfLocalDayMs(countdown.getShiftEndAtMs(previous), timeZone),
        1,
        timeZone
      );
      if (anchorMs < targetAtMs) return anchorMs;
    }
    return targetDayMs;
  }

  function countdownProjection(input, shift, nextShift) {
    const shiftStartAtMs = countdown.getShiftStartAtMs(shift);
    const targetAtMs = input.nowMs < shiftStartAtMs && isActualShift(input, shift)
      ? shiftStartAtMs
      : nextShift
        ? countdown.getShiftStartAtMs(nextShift)
        : null;
    if (!(typeof targetAtMs === "number") || targetAtMs <= input.nowMs) {
      return { targetAtMs: null, anchorAtMs: null, progress: 0 };
    }

    const targetDayAtMs = startOfLocalDayMs(targetAtMs, inputTimeZone(input));
    const isTargetWorkday = input.nowMs >= targetDayAtMs;
    const anchorAtMs = isTargetWorkday
      ? targetDayAtMs
      : countdownAnchorAtMs(input, targetAtMs);
    const progressEndAtMs = isTargetWorkday ? targetAtMs : targetDayAtMs;
    const durationMs = progressEndAtMs - anchorAtMs;
    const progress = durationMs > 0
      ? Math.max(0, Math.min(100, (input.nowMs - anchorAtMs) / durationMs * 100))
      : 0;
    return { targetAtMs, anchorAtMs, progress };
  }

  function nextShiftAfter(input, shift) {
    return countdown.findNextShiftTimeline({
      startTime: input.startTime,
      endTime: input.endTime,
      workdays: input.workdays,
      schedule: input.schedule || null,
      afterMs: Math.max(input.nowMs, countdown.getShiftEndAtMs(shift)),
      options: {
        breakStartTime: input.breakStartTime || null,
        breakDurationMinutes: input.breakDurationMinutes || 0,
      },
      timeZone: inputTimeZone(input),
    });
  }

  global.OWCScheduleOracle = {
    watchProjection(requestJSON) {
      const request = JSON.parse(requestJSON);
      const input = request.rules;
      const shift = resolveCurrentShift(input);
      const nextShift = nextShiftAfter(input, shift);
      const currentIsActual = isActualShift(input, shift);
      return JSON.stringify(watchProjection.projectWatchSnapshot({
        nowMs: input.nowMs,
        scheduleConfigured: Boolean(request.scheduleConfigured),
        isRunning: Boolean(request.isRunning),
        currentShift: shift,
        currentShiftOverride: request.currentShift || null,
        finishedAtMs: request.finishedAtMs || null,
        currentIsActual,
        nextShift,
        timeZone: inputTimeZone(input),
      }));
    },

    snapshot(inputJSON) {
      const input = JSON.parse(inputJSON);
      const shift = resolveCurrentShift(input);
      const nextShift = nextShiftAfter(input, shift);
      const clockIn = countdownProjection(input, shift, nextShift);
      const dailySalary = countdown.getDailySalary(
        String(input.salaryAmount ?? ""),
        input.salaryType,
        input.monthlyWorkingDays,
        input.annualBonusMonths || 0
      );
      const payRatio = countdown.calculateTimelinePayRatio(shift, input.nowMs);
      return JSON.stringify({
        segments: shift.segments,
        startAtMs: countdown.getShiftStartAtMs(shift),
        endAtMs: countdown.getShiftEndAtMs(shift),
        plannedEndAtMs: shift.plannedEndAtMs,
        overtimeEndAtMs: shift.overtimeEndAtMs,
        durationMs: countdown.getShiftDurationMs(shift),
        plannedDurationMs: countdown.getPlannedShiftDurationMs(shift),
        elapsedMs: countdown.getShiftElapsedMs(shift, input.nowMs),
        remainingMs: countdown.getShiftRemainingMs(shift, input.nowMs),
        progress: countdown.calculateTimelineProgress(shift, input.nowMs),
        payRatio,
        activeBreakEndAtMs: countdown.getActiveBreakEndAtMs(shift, input.nowMs),
        isWorkday: countdown.isScheduledWorkday(
          new Date(countdown.getShiftStartAtMs(shift)),
          input.workdays,
          input.schedule || null,
          inputTimeZone(input)
        ),
        nextRestAtMs: countdown.findNextRestDate({
          afterMs: input.nowMs,
          workdays: input.workdays,
          schedule: input.schedule || null,
          timeZone: inputTimeZone(input),
        })?.getTime() ?? null,
        dailySalary,
        earnedSoFar: summary.earningsForRatio(dailySalary, payRatio),
        nextShiftStartAtMs: nextShift
          ? countdown.getShiftStartAtMs(nextShift)
          : null,
        nextShiftEndAtMs: nextShift
          ? countdown.getShiftEndAtMs(nextShift)
          : null,
        countdownTargetAtMs: clockIn.targetAtMs,
        countdownAnchorAtMs: clockIn.anchorAtMs,
        countdownProgress: clockIn.progress,
      });
    },

    widgetShifts(inputJSON) {
      const request = JSON.parse(inputJSON);
      const input = request.rules;
      const throughMs = Number(request.throughMs);
      const maximumCount = Math.max(0, Math.floor(request.maximumCount || 0));
      const current = countdown.buildShiftTimeline(
        input.startTime,
        input.endTime,
        new Date(input.nowMs),
        shiftOptions(input),
        inputTimeZone(input)
      );
      const shifts = [];
      let afterMs = Math.max(input.nowMs, countdown.getShiftEndAtMs(current));

      while (shifts.length < maximumCount) {
        const shift = countdown.findNextShiftTimeline({
          startTime: input.startTime,
          endTime: input.endTime,
          workdays: input.workdays,
          schedule: input.schedule || null,
          afterMs,
          options: {
            breakStartTime: input.breakStartTime || null,
            breakDurationMinutes: input.breakDurationMinutes || 0,
          },
          timeZone: inputTimeZone(input),
        });
        if (!shift) break;

        const startAtMs = countdown.getShiftStartAtMs(shift);
        const endAtMs = countdown.getShiftEndAtMs(shift);
        shifts.push({
          segments: shift.segments,
          startAtMs,
          endAtMs,
          plannedEndAtMs: shift.plannedEndAtMs,
          overtimeEndAtMs: shift.overtimeEndAtMs,
          durationMs: countdown.getShiftDurationMs(shift),
          countdownAnchorAtMs: countdownAnchorAtMs(input, startAtMs),
        });
        // Include the first shift beyond the horizon as a countdown target.
        // Swift caps its interval at snapshot expiry and does not render that
        // shift, but the preceding rest days still count toward a real date.
        if (startAtMs >= throughMs) break;
        if (endAtMs <= afterMs) break;
        afterMs = endAtMs;
      }
      return JSON.stringify(shifts);
    },

    expandScheduleRange(inputJSON) {
      const input = JSON.parse(inputJSON);
      return JSON.stringify(countdown.expandScheduleRange({
        startTime: input.startTime,
        endTime: input.endTime,
        workdays: input.workdays,
        schedule: input.schedule || null,
        breakStartTime: input.breakStartTime || null,
        breakDurationMinutes: input.breakDurationMinutes || 0,
        fromMs: Number(input.fromMs),
        throughMs: Number(input.throughMs),
        timeZone: input.timeZoneIdentifier || null,
      }));
    },

    validateBreak(inputJSON) {
      const input = JSON.parse(inputJSON);
      if (!input.breakStartTime || !(input.breakDurationMinutes > 0)) return true;
      return countdown.buildShiftTimeline(
        input.startTime,
        input.endTime,
        new Date(input.nowMs),
        shiftOptions(input),
        inputTimeZone(input)
      ).segments.length > 1;
    },

    reminders(inputJSON) {
      const input = JSON.parse(inputJSON);
      const shift = resolveCurrentShift(input);
      const nextShift = nextShiftAfter(input, shift);
      const project = (timeline, scope) =>
        reminders
          .buildShiftReminders(timeline, input.reminderInputs)
          .map((reminder) => ({
            ...reminder,
            id: scope + ":" + countdown.getShiftEndAtMs(timeline) + ":" + reminder.id,
          }));
      return JSON.stringify(
        [
          ...project(shift, "current"),
          ...(nextShift ? project(nextShift, "next") : []),
        ].sort((left, right) => left.atMs - right.atMs)
      );
    },

    // A settled shift is still today's durable Records row, and even a
    // finished lunch changes its allocation, so neither the kind of edit nor
    // the clock narrows this: ask whenever either timeline is scheduled today.
    shouldPromptApplyToday(requestJSON) {
      const request = JSON.parse(requestJSON);
      return isScheduledShift(request.current, resolveCurrentShift(request.current)) ||
        isScheduledShift(request.candidate, resolveCurrentShift(request.candidate));
    },
  };
`;

export function createScheduleRuleOracleScript() {
  return createRulesScript({
    header: "// Schedule-rule oracle for plan 019 R1 and R2 fixtures. Not shipped.",
    moduleNames: ["./countdown", "./reminders", "./summary", "./watch-projection"],
    body: ORACLE_BODY,
  });
}

/** The TypeScript entry points, each taking and returning a JSON string. */
export function loadScheduleRuleOracle() {
  const context = vm.createContext({ console });
  vm.runInContext(createScheduleRuleOracleScript(), context);
  return context.OWCScheduleOracle;
}
