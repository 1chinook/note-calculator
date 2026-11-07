const STORAGE_KEY = "not-hesaplama-v2";
const COLORS = ["#648f86", "#c7795b", "#7b82b4", "#c39b4a", "#9c6f91", "#5f86a5"];

const INITIAL_COURSES = [
  ["Soyut Matematik I", 3],
  ["Nümerik Analiz I", 3],
  ["Soyut Cebir I", 4],
  ["Diferansiyel Geometri", 4],
  ["Kompleks Analiz", 4],
  ["Seç. Mat. V: Fark Denklemleri I", 3],
  ["Topoloji I", 4],
  ["Seç. Mat. III: Uygulamalı Matematik", 3],
  ["Analitik Geometri I", 3],
  ["Diferansiyel Denklemler I", 4],
  ["Seç. Bil. II: Algoritmalar", 3],
  ["Bitirme Çalışması I", 3],
  ["Girişimcilik Kültürü", 1],
];

const state = loadState();
let selectedColor = COLORS[0];
let compactView = localStorage.getItem("not-hesaplama-compact") === "true";

const ui = {
  courseList: document.querySelector("#courseList"),
  emptyState: document.querySelector("#emptyState"),
  courseCount: document.querySelector("#courseCount"),
  overallAverage: document.querySelector("#overallAverage"),
  overallSubtitle: document.querySelector("#overallSubtitle"),
  courseDialog: document.querySelector("#courseDialog"),
  courseForm: document.querySelector("#courseForm"),
  courseName: document.querySelector("#courseName"),
  courseCredit: document.querySelector("#courseCredit"),
  colorOptions: document.querySelector("#colorOptions"),
  examDialog: document.querySelector("#examDialog"),
  examForm: document.querySelector("#examForm"),
  examCourseId: document.querySelector("#examCourseId"),
  examId: document.querySelector("#examId"),
  examName: document.querySelector("#examName"),
  examScore: document.querySelector("#examScore"),
  examWeight: document.querySelector("#examWeight"),
  examDialogTitle: document.querySelector("#examDialogTitle"),
  weightHint: document.querySelector("#weightHint"),
  courseTemplate: document.querySelector("#courseTemplate"),
  toggleCompact: document.querySelector("#toggleCompact"),
};

function createSeedCourse(name, credit, index) {
  return {
    id: uid(),
    name,
    credit,
    color: COLORS[index % COLORS.length],
    exams: [
      { id: uid(), name: "Vize", score: null, weight: 37.5 },
      { id: uid(), name: "Kısa Sınav", score: null, weight: 12.5 },
      { id: uid(), name: "Final", score: null, weight: 50 },
    ],
  };
}

function loadState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (saved && Array.isArray(saved.courses)) {
      saved.courses.forEach((course) => {
        if (!Number(course.credit)) course.credit = 3;
      });
      INITIAL_COURSES.forEach(([name, credit], index) => {
        if (!saved.courses.some((course) => course.name === name)) {
          saved.courses.push(createSeedCourse(name, credit, index));
        }
      });
      return saved;
    }
  } catch (_) {}
  return {
    courses: INITIAL_COURSES.map(([name, credit], index) => createSeedCourse(name, credit, index)),
  };
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function uid() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function formatNumber(value) {
  return Number(value).toLocaleString("tr-TR", { maximumFractionDigits: 2 });
}

function courseStats(course) {
  const totalWeight = course.exams.reduce((sum, exam) => sum + Number(exam.weight), 0);
  const gradedExams = course.exams.filter((exam) => exam.score !== null && exam.score !== "");
  const gradedWeight = gradedExams.reduce((sum, exam) => sum + Number(exam.weight), 0);
  const weightedPoints = gradedExams.reduce(
    (sum, exam) => sum + Number(exam.score) * Number(exam.weight) / 100,
    0,
  );
  const finalExam = course.exams.find((exam) => exam.name.toLocaleLowerCase("tr-TR").includes("final"));
  const hasFinalScore = Boolean(finalExam && finalExam.score !== null && finalExam.score !== "");
  const normalizedAverage = gradedWeight > 0 ? weightedPoints : null;
  return { totalWeight, gradedWeight, weightedPoints, normalizedAverage, hasFinalScore };
}

function letterGrade(average) {
  if (average === null) return "—";
  if (average >= 90) return "AA";
  if (average >= 85) return "BA";
  if (average >= 80) return "BB";
  if (average >= 75) return "CB";
  if (average >= 70) return "CC";
  if (average >= 65) return "DC";
  if (average >= 60) return "DD";
  if (average >= 50) return "FD";
  return "FF";
}

function render() {
  ui.courseList.innerHTML = "";
  ui.courseList.classList.toggle("compact", compactView);
  ui.toggleCompact.setAttribute("aria-pressed", String(compactView));
  ui.toggleCompact.textContent = compactView ? "▦ Normal görünüm" : "▦ Kompakt görünüm";
  state.courses.forEach(renderCourse);

  const hasCourses = state.courses.length > 0;
  ui.emptyState.hidden = hasCourses;
  ui.courseList.hidden = !hasCourses;
  ui.courseCount.textContent = `${state.courses.length} ders`;

  const completed = state.courses
    .map(courseStats)
    .filter((stats) => stats.hasFinalScore);
  if (completed.length) {
    const includedCourses = state.courses.filter((course) => courseStats(course).hasFinalScore);
    const creditTotal = includedCourses.reduce((sum, course) => sum + Number(course.credit || 0), 0);
    const average = creditTotal > 0
      ? includedCourses.reduce((sum, course) => sum + courseStats(course).normalizedAverage * Number(course.credit), 0) / creditTotal
      : completed.reduce((sum, item) => sum + item.normalizedAverage, 0) / completed.length;
    ui.overallAverage.textContent = formatNumber(average);
    ui.overallSubtitle.textContent = `${formatNumber(creditTotal)} kredi • ${completed.length} ders`;
  } else {
    ui.overallAverage.textContent = "—";
    ui.overallSubtitle.textContent = "Henüz hesaplanmadı";
  }
}

function renderCourse(course) {
  const fragment = ui.courseTemplate.content.cloneNode(true);
  const card = fragment.querySelector(".course-card");
  const accent = fragment.querySelector(".course-accent");
  const nameInput = fragment.querySelector(".course-name-input");
  const examList = fragment.querySelector(".exam-list");
  const creditInput = fragment.querySelector(".course-credit-input");
  const stats = courseStats(course);

  card.dataset.courseId = course.id;
  accent.style.background = course.color;
  nameInput.value = course.name;
  nameInput.addEventListener("change", () => {
    const newName = nameInput.value.trim();
    nameInput.value = newName || course.name;
    if (newName) {
      course.name = newName;
      saveState();
    }
  });

  creditInput.value = course.credit;
  creditInput.addEventListener("change", () => {
    const value = Number(creditInput.value);
    if (value >= 0.5 && value <= 30) {
      course.credit = value;
      saveState();
      render();
    } else {
      creditInput.value = course.credit;
    }
  });

  fragment.querySelector(".course-average").textContent = stats.normalizedAverage === null
    ? "—"
    : formatNumber(stats.normalizedAverage);
  fragment.querySelector(".letter-grade").textContent = stats.hasFinalScore
    ? letterGrade(stats.normalizedAverage)
    : "—";

  const totalWeight = fragment.querySelector(".total-weight");
  totalWeight.textContent = `%${formatNumber(stats.totalWeight)}`;
  totalWeight.className = `total-weight ${stats.totalWeight === 100 ? "complete" : stats.totalWeight > 100 ? "error" : "warning"}`;

  const track = fragment.querySelector(".weight-track span");
  track.style.width = `${Math.min(stats.totalWeight, 100)}%`;
  if (stats.totalWeight > 100) track.classList.add("error");

  if (!course.exams.length) {
    examList.innerHTML = '<div class="no-exams">Henüz sınav eklenmedi.</div>';
  } else {
    course.exams.forEach((exam) => examList.append(createExamRow(course, exam)));
  }

  fragment.querySelector(".add-exam").addEventListener("click", () => openExamDialog(course.id));
  fragment.querySelector(".delete-course").addEventListener("click", () => deleteCourse(course.id));
  ui.courseList.append(fragment);
}

function createExamRow(course, exam) {
  const row = document.createElement("div");
  row.className = "exam-row";
  row.innerHTML = `
    <button class="exam-name edit-exam" type="button" aria-label="${escapeHtml(exam.name)} sınavını düzenle">${escapeHtml(exam.name)}</button>
    <button class="exam-score edit-exam" type="button" aria-label="${escapeHtml(exam.name)} notunu düzenle">${exam.score === null || exam.score === "" ? "Not gir" : formatNumber(exam.score)}</button>
    <button class="exam-weight edit-exam" type="button" aria-label="${escapeHtml(exam.name)} ağırlığını düzenle">%${formatNumber(exam.weight)}</button>
    <button class="delete-exam" type="button" aria-label="${escapeHtml(exam.name)} sınavını sil">×</button>
  `;
  row.querySelectorAll(".edit-exam").forEach((button) => {
    button.addEventListener("click", () => openExamDialog(course.id, exam.id));
  });
  row.querySelector(".delete-exam").addEventListener("click", () => {
    course.exams = course.exams.filter((item) => item.id !== exam.id);
    saveState();
    render();
  });
  return row;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[char]);
}

function openCourseDialog() {
  ui.courseForm.reset();
  ui.courseCredit.value = 3;
  selectedColor = COLORS[state.courses.length % COLORS.length];
  renderColors();
  ui.courseDialog.showModal();
  setTimeout(() => ui.courseName.focus(), 0);
}

function renderColors() {
  ui.colorOptions.innerHTML = "";
  COLORS.forEach((color) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `color-option${selectedColor === color ? " selected" : ""}`;
    button.style.background = color;
    button.setAttribute("aria-label", `Ders rengi ${color}`);
    button.addEventListener("click", () => {
      selectedColor = color;
      renderColors();
    });
    ui.colorOptions.append(button);
  });
}

function openExamDialog(courseId, examId = "") {
  const course = state.courses.find((item) => item.id === courseId);
  if (!course) return;
  const exam = course.exams.find((item) => item.id === examId);

  ui.examForm.reset();
  ui.examCourseId.value = courseId;
  ui.examId.value = examId;
  ui.examDialogTitle.textContent = exam ? "Sınavı düzenle" : "Sınav ekle";
  if (exam) {
    ui.examName.value = exam.name;
    ui.examScore.value = exam.score ?? "";
    ui.examWeight.value = exam.weight;
  }
  updateWeightHint();
  ui.examDialog.showModal();
  setTimeout(() => ui.examName.focus(), 0);
}

function updateWeightHint() {
  const course = state.courses.find((item) => item.id === ui.examCourseId.value);
  if (!course) return;
  const otherTotal = course.exams
    .filter((item) => item.id !== ui.examId.value)
    .reduce((sum, item) => sum + Number(item.weight), 0);
  const nextTotal = otherTotal + Number(ui.examWeight.value || 0);
  ui.weightHint.textContent = `Bu kayıtla ağırlık toplamı %${formatNumber(nextTotal)} olacak.`;
  ui.weightHint.classList.toggle("error", nextTotal > 100);
}

function deleteCourse(courseId) {
  const course = state.courses.find((item) => item.id === courseId);
  if (!course) return;
  if (!confirm(`“${course.name}” dersi ve sınavları silinsin mi?`)) return;
  state.courses = state.courses.filter((item) => item.id !== courseId);
  saveState();
  render();
}

ui.courseForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const name = ui.courseName.value.trim();
  if (!name) return;
  const credit = Number(ui.courseCredit.value);
  state.courses.push({ id: uid(), name, credit, color: selectedColor, exams: [] });
  saveState();
  ui.courseDialog.close();
  render();
});

ui.examForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const course = state.courses.find((item) => item.id === ui.examCourseId.value);
  if (!course) return;

  const values = {
    name: ui.examName.value.trim(),
    score: ui.examScore.value === "" ? null : Number(ui.examScore.value),
    weight: Number(ui.examWeight.value),
  };
  if (!values.name || (values.score !== null && (values.score < 0 || values.score > 100)) || values.weight < 0 || values.weight > 100) return;

  const existing = course.exams.find((item) => item.id === ui.examId.value);
  if (existing) Object.assign(existing, values);
  else course.exams.push({ id: uid(), ...values });

  saveState();
  ui.examDialog.close();
  render();
});

["addCourseTop", "addCourse", "addFirstCourse"].forEach((id) => {
  document.querySelector(`#${id}`).addEventListener("click", openCourseDialog);
});
document.querySelector("#closeCourseDialog").addEventListener("click", () => ui.courseDialog.close());
document.querySelector("#cancelCourse").addEventListener("click", () => ui.courseDialog.close());
document.querySelector("#closeExamDialog").addEventListener("click", () => ui.examDialog.close());
document.querySelector("#cancelExam").addEventListener("click", () => ui.examDialog.close());
ui.examWeight.addEventListener("input", updateWeightHint);
ui.toggleCompact.addEventListener("click", () => {
  compactView = !compactView;
  localStorage.setItem("not-hesaplama-compact", String(compactView));
  render();
});

render();
