import meta from "../../../pages/_meta.js";
import zh_meta from "../../../pages/zh/_meta.js";
export const pageMap = [{
  data: meta
}, {
  name: "devices",
  route: "/devices",
  frontMatter: {
    "sidebarTitle": "Devices"
  }
}, {
  name: "faq",
  route: "/faq",
  frontMatter: {
    "sidebarTitle": "Faq"
  }
}, {
  name: "index",
  route: "/",
  frontMatter: {
    "title": "Flutter RTC Link"
  }
}, {
  name: "installation",
  route: "/installation",
  frontMatter: {
    "sidebarTitle": "Installation"
  }
}, {
  name: "publishing",
  route: "/publishing",
  frontMatter: {
    "sidebarTitle": "Publishing"
  }
}, {
  name: "quick-start",
  route: "/quick-start",
  frontMatter: {
    "sidebarTitle": "Quick Start"
  }
}, {
  name: "resilience",
  route: "/resilience",
  frontMatter: {
    "sidebarTitle": "Resilience"
  }
}, {
  name: "robot",
  route: "/robot",
  frontMatter: {
    "sidebarTitle": "Robot"
  }
}, {
  name: "subscribing",
  route: "/subscribing",
  frontMatter: {
    "sidebarTitle": "Subscribing"
  }
}, {
  name: "zh",
  route: "/zh",
  children: [{
    data: zh_meta
  }, {
    name: "devices",
    route: "/zh/devices",
    frontMatter: {
      "sidebarTitle": "Devices"
    }
  }, {
    name: "faq",
    route: "/zh/faq",
    frontMatter: {
      "sidebarTitle": "Faq"
    }
  }, {
    name: "index",
    route: "/zh",
    frontMatter: {
      "title": "Flutter RTC Link"
    }
  }, {
    name: "installation",
    route: "/zh/installation",
    frontMatter: {
      "sidebarTitle": "Installation"
    }
  }, {
    name: "publishing",
    route: "/zh/publishing",
    frontMatter: {
      "sidebarTitle": "Publishing"
    }
  }, {
    name: "quick-start",
    route: "/zh/quick-start",
    frontMatter: {
      "sidebarTitle": "Quick Start"
    }
  }, {
    name: "resilience",
    route: "/zh/resilience",
    frontMatter: {
      "sidebarTitle": "Resilience"
    }
  }, {
    name: "robot",
    route: "/zh/robot",
    frontMatter: {
      "sidebarTitle": "Robot"
    }
  }, {
    name: "subscribing",
    route: "/zh/subscribing",
    frontMatter: {
      "sidebarTitle": "Subscribing"
    }
  }]
}];